#!/usr/bin/env python3
"""
Tests concurrent multi-slot serving on llama-server (-np 2).
Fires parallel requests and measures aggregate throughput and latency.
"""
import subprocess
import time
import requests
import json
import concurrent.futures
import os
import signal

PORT = 8089
SERVER_BIN = "/home/user/source/llama.cpp-strix-halo-vulkan/build/bin/llama-server"
MODEL_PATH = "/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf"
DRAFT_PATH = "/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf"

server_cmd = [
    SERVER_BIN,
    "-m", MODEL_PATH,
    "-md", DRAFT_PATH,
    "--spec-type", "draft-mtp",
    "--spec-draft-n-max", "6",
    "--spec-draft-p-min", "0.75",
    "-dev", "Vulkan0",
    "-ngl", "999",
    "-fa", "on",
    "-ub", "1024",
    "-b", "2048",
    "-ctk", "q8_0",
    "-ctv", "q8_0",
    "-t", "4",
    "-tb", "16",
    "-lm", "mmap",
    "--tensor-read-lazy", "on",
    "--cache-ram", "4096",
    "-c", "32768",
    "-np", "2",
    "--port", str(PORT),
    "--host", "127.0.0.1",
    "--reasoning", "off"
]

def wait_for_server(timeout=180):
    start = time.time()
    url = f"http://127.0.0.1:{PORT}/health"
    while time.time() - start < timeout:
        try:
            r = requests.get(url, timeout=1)
            if r.status_code == 200:
                print("Server is healthy and ready!")
                return True
        except Exception:
            pass
        time.sleep(1)
    return False

def send_request(client_id, prompt, n_predict=64):
    url = f"http://127.0.0.1:{PORT}/completion"
    payload = {
        "prompt": prompt,
        "n_predict": n_predict,
        "temperature": 0.0,
        "stream": False
    }
    t0 = time.time()
    resp = requests.post(url, json=payload, timeout=300)
    elapsed = time.time() - t0
    data = resp.json()
    tokens_gen = data.get("tokens_predicted", 0)
    tokens_eval = data.get("tokens_evaluated", 0)
    t_pp = data.get("timings", {}).get("prompt_per_second", 0)
    t_tg = data.get("timings", {}).get("predicted_per_second", 0)
    return {
        "client_id": client_id,
        "elapsed_s": elapsed,
        "tokens_gen": tokens_gen,
        "tokens_eval": tokens_eval,
        "tg_per_sec": t_tg,
        "pp_per_sec": t_pp,
        "text": data.get("content", "")[:60].replace("\n", " ")
    }

def main():
    print(f"Starting llama-server with 2 slots (-np 2) on port {PORT}...")
    log_file = open("/home/user/source/haloq38flash/results/concurrent-server.log", "w")
    proc = subprocess.Popen(server_cmd, stdout=log_file, stderr=subprocess.STDOUT)
    
    try:
        if not wait_for_server(180):
            print("ERROR: Server failed to start within timeout.")
            return

        # Check memory
        mem = subprocess.check_output(["free", "-h"]).decode()
        print(f"Memory after server start:\n{mem}")

        prompts = [
            ("Client-1", "Explain the concept of quantum entanglement in simple terms."),
            ("Client-2", "Write a python script that implements a quicksort algorithm.")
        ]

        print("Firing 2 simultaneous requests...")
        t_start = time.time()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(send_request, cid, p, 64) for cid, p in prompts]
            results = [f.result() for f in futures]
        total_time = time.time() - t_start

        total_tokens = sum(r["tokens_gen"] for r in results)
        agg_tps = total_tokens / total_time if total_time > 0 else 0

        print(f"\n=== Concurrency Results (2 slots) ===")
        for r in results:
            print(f"[{r['client_id']}] elapsed: {r['elapsed_s']:.2f}s | gen: {r['tokens_gen']} tok ({r['tg_per_sec']:.1f} t/s) | eval: {r['tokens_eval']} tok | sample: '{r['text']}'")
        print(f"Total time: {total_time:.2f}s | Aggregate Generation: {agg_tps:.1f} total tokens/sec")

    finally:
        print("Stopping server...")
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
        log_file.close()

if __name__ == "__main__":
    main()
