# haloq38flash — qwen3.8-flash-next on strix halo (vulkan/radv)
# builds the halo-box strix-llama.cpp engine (commit 5f851647f) and serves with the
# recommended flags. models are mounted, not baked in.

# ---- stage 1: build ----
FROM ubuntu:24.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential cmake ninja-build git ccache \
    libvulkan-dev glslc vulkan-tools \
    spirv-headers spirv-tools glslang-dev libshaderc-dev \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

COPY patches/ /patches/
RUN git clone https://github.com/halo-box/strix-llama.cpp /src/engine \
    && cd /src/engine \
    && git fetch origin dff60048744f99cb0af68d02be2314456b3269dc \
    && git checkout FETCH_HEAD \
    && git apply /patches/0001-mtp-recurrent-rollback-qwen4exp.patch

RUN cmake -B /src/engine/build -S /src/engine \
    -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -G Ninja \
    && cmake --build /src/engine/build --parallel $(nproc) \
       --target llama-server llama-cli llama-bench llama-perplexity

# ---- stage 2: runtime ----
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# add kisak ppa for recent mesa/radv (gfx1151 needs >= 24.x)
RUN apt-get update && apt-get install -y software-properties-common gpg-agent \
    && add-apt-repository -y ppa:kisak/kisak-mesa \
    && apt-get update && apt-get install -y \
    mesa-vulkan-drivers vulkan-tools libvulkan1 \
    libgomp1 libcurl4 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/engine/build/bin/llama-server /app/llama-server
COPY --from=build /src/engine/build/bin/llama-cli /app/llama-cli
COPY --from=build /src/engine/build/bin/llama-bench /app/llama-bench
COPY --from=build /src/engine/build/bin/llama-perplexity /app/llama-perplexity
COPY --from=build /src/engine/build/bin/*.so* /app/

RUN ldconfig /app 2>/dev/null; true
ENV LD_LIBRARY_PATH=/app
ENV PATH="/app:${PATH}"
ENV RADV_PERFTEST=unified_heap
ENV GGML_VK_MAX_MB_PER_SUBMIT=2048
ENV GGML_VK_MMID_ROWLISTS=1
ENV GGML_VK_MMID_SMALLN=1
ENV GGML_VK_MMID_BM64=1
ENV GGML_VK_MMID_WAVE32=1
ENV GGML_VK_MMID_F16B=1
ENV GGML_VK_MMID_M128=1
ENV GGML_VK_FA_WAVE32=0

# models volume
VOLUME /models

WORKDIR /app
EXPOSE 8080

CMD ["/app/llama-server", \
     "-m", "/models/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf", \
     "-md", "/models/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf", \
     "--spec-type", "draft-mtp", \
     "--spec-draft-n-max", "6", \
     "--spec-draft-p-min", "0.75", \
     "-dev", "Vulkan0", "-ngl", "999", "-fa", "on", \
     "-c", "257024", "-ub", "2048", "-b", "4096", \
     "-ctk", "q8_0", "-ctv", "q8_0", \
     "-t", "4", "-tb", "16", \
     "-lm", "mmap", "-lzm", "on", \
     "--cache-ram", "8192", "--ctx-checkpoints", "32", "--cache-prompt", \
     "--jinja", "--host", "0.0.0.0", "--port", "8080"]
