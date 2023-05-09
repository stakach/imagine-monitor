FROM 84codes/crystal:latest-debian-11 as build
WORKDIR /app

# Update system and install required packages
RUN apt-get update && apt-get install -y \
    gnupg \
    wget \
    curl \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add Google Cloud public key
RUN wget -q -O - https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/coral-edgetpu.gpg

# Add Coral packages repository
RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/coral-edgetpu.gpg] https://packages.cloud.google.com/apt coral-edgetpu-stable main" | tee /etc/apt/sources.list.d/coral-edgetpu.list

# Add dependencies commonly required for building crystal applications
# hadolint ignore=DL3018
RUN apt update && apt install -y \
    build-essential \
    cmake \
    linux-headers-generic \
    git \
    wget \
    python3 \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libswscale-dev \
    ca-certificates \
    opencl-headers \
    libopencv-core-dev \
    clang-format-9 \
    libedgetpu-dev \
    libedgetpu1-std

# Install shards for caching
COPY shard.yml shard.yml
COPY shard.override.yml shard.override.yml
COPY shard.lock shard.lock

RUN shards install --production --ignore-crystal-version --skip-postinstall --skip-executables

# Compile Tensorflow lite and put it in place
RUN git clone --depth 1 https://github.com/tensorflow/tensorflow
RUN mkdir tfbuild
WORKDIR /app/tfbuild
RUN cmake ../tensorflow/tensorflow/lite/c -DTFLITE_ENABLE_GPU=ON
RUN cmake --build . -j4 || true
RUN echo "---------- WE ARE BUILDING AGAIN!! ----------"
RUN cmake --build . -j1
RUN mkdir -p ../lib/tensorflow_lite/ext
RUN mkdir -p ../bin
RUN cp ./libtensorflowlite_c.so ../lib/tensorflow_lite/ext/
RUN cp ./libtensorflowlite_c.so ../bin/

WORKDIR /app
COPY ./src /app/src

# Build application
# RUN shards build --production --release --error-trace
RUN shards build --production --error-trace -Dpreview_mt

# Extract binary dependencies (uncomment if not compiling a static build)
RUN for binary in /app/bin/*; do \
        ldd "$binary" | \
        tr -s '[:blank:]' '\n' | \
        grep '^/' | \
        xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'; \
    done

# Generate OpenAPI docs while we still have source code access
RUN ./bin/monitor --docs --file=openapi.yml
RUN update-ca-certificates
RUN mkdir ./models

# Build a minimal docker image
FROM debian:stable-slim
WORKDIR /
ENV PATH=$PATH:/

# Update system and install required packages
RUN apt-get update && apt-get install -y \
    gnupg \
    wget \
    curl \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add Google Cloud public key
RUN wget -q -O - https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/coral-edgetpu.gpg

# Add Coral packages repository
RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/coral-edgetpu.gpg] https://packages.cloud.google.com/apt coral-edgetpu-stable main" | tee /etc/apt/sources.list.d/coral-edgetpu.list

# Install Edge TPU runtime
RUN apt-get update \
    && apt-get install -y libedgetpu1-std \
    && rm -rf /var/lib/apt/lists/*

# This is required for Timezone support
COPY --from=build /usr/share/zoneinfo/ /usr/share/zoneinfo/

# This is your application
COPY --from=build /app/deps /
COPY --from=build /app/bin /app/bin
COPY --from=build /app/models /models
COPY ./www /www

# Copy the docs into the container, you can serve this file in your app
COPY --from=build /app/openapi.yml /openapi.yml

# Run the app binding on host for multicast access
ENTRYPOINT ["/app/bin/monitor"]
CMD ["/app/bin/monitor"]
