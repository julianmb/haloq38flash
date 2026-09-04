# haloq38flash — qwen3.8-flash-next on strix halo (vulkan/radv)
# builds the nathanw1014 strix-halo-vulkan engine and serves with the
# recommended flags. models are mounted, not baked in.

# ---- stage 1: build ----
FROM ubuntu:24.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential cmake ninja-build git ccache \
    libvulkan-dev glslc vulkan-tools \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 -b strix-halo-vulkan \
    https://github.com/Nathanw1014/llama.cpp /src/engine
RUN cmake -B /src/engine/build -S /src/engine \
    -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON \
    -DLLAMA_CURL=ON \
    && cmake --build /src/engine/build --parallel $(nproc) \
       --target llama-server llama-cli llama-bench

# ---- stage 2: runtime ----
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# add kisak ppa for recent mesa/radv (gfx1151 needs >= 24.x)
RUN apt-get update && apt-get install -y software-properties-common gpg-agent \
    && add-apt-repository -y ppa:kisak/kisak \
    && apt-get update && apt-get install -y \
    mesa-vulkan-drivers vulkan-tools libvulkan1 \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/engine/build/bin/llama-server /app/llama-server
COPY --from=build /src/engine/build/bin/llama-cli /app/llama-cli
COPY --from=build /src/engine/build/bin/llama-bench /app/llama-bench
COPY --from=build /src/engine/build/bin/libggml*.so* /app/
COPY --from=build /src/engine/build/bin/libllama*.so* /app/

RUN ldconfig /app 2>/dev/null; true
ENV LD_LIBRARY_PATH=/app

# models volume
VOLUME /models

WORKDIR /app
EXPOSE 8080

CMD ["/app/llama-server", \
     "-m", "/models/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf", \
     "-ngl", "999", "-fa", "on", \
     "-ctk", "q8_0", "-ctv", "q8_0", \
     "-c", "32768", "-ub", "2048", "-t", "4", \
     "--cache-ram", "8192", "--ctx-checkpoints", "32", \
     "--jinja", "--host", "0.0.0.0", "--port", "8080"]
