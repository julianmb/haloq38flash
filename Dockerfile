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

RUN git clone https://github.com/halo-box/strix-llama.cpp /src/engine \
    && cd /src/engine \
    && git checkout 5f851647f

RUN cmake -B /src/engine/build -S /src/engine \
    -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON \
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
ENV RADV_PERFTEST=unified_heap
ENV GGML_VK_MAX_MB_PER_SUBMIT=2048

# models volume
VOLUME /models

WORKDIR /app
EXPOSE 8080

CMD ["/app/llama-server", \
     "-m", "/models/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf", \
     "-md", "/models/mtp-Qwen3.8-Flash-Next-Q8_0.gguf", \
     "--spec-type", "draft-mtp", \
     "--spec-draft-n-max", "6", \
     "--spec-draft-p-min", "0.75", \
     "-dev", "Vulkan0", "-ngl", "999", "-fa", "on", \
     "-c", "40960", "-ub", "1024", "-b", "4096", \
     "-ctk", "q8_0", "-ctv", "q8_0", \
     "-t", "4", "-tb", "16", \
     "-lm", "mmap", "-lzm", "on", \
     "--cache-ram", "8192", "--ctx-checkpoints", "32", "--cache-prompt", \
     "--jinja", "--host", "0.0.0.0", "--port", "8080"]
