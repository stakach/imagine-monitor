FROM 84codes/crystal:latest-debian-11 as build
WORKDIR /app

# Create a non-privileged user, defaults are appuser:10001
ARG IMAGE_UID="10001"
ENV UID=$IMAGE_UID
ENV USER=appuser

# See https://stackoverflow.com/a/55757473/12429735
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

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
    clang-format-9

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
RUN cmake --build . -j2 || true
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
RUN shards build --production --error-trace

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
FROM scratch
WORKDIR /
ENV PATH=$PATH:/

# Copy the user information over
COPY --from=build /etc/passwd /etc/passwd
COPY --from=build /etc/group /etc/group

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# This is required for Timezone support
COPY --from=build /usr/share/zoneinfo/ /usr/share/zoneinfo/

# This is your application
COPY --from=build /app/deps /
COPY --from=build /app/bin /app/bin
COPY --from=build /app/models /models

# Copy the docs into the container, you can serve this file in your app
COPY --from=build /app/openapi.yml /openapi.yml

# Use an unprivileged user.
USER appuser:appuser

# Spider-gazelle has a built in helper for health checks (change this as desired for your applications)
HEALTHCHECK CMD ["/app/bin/monitor", "-c", "http://127.0.0.1:3000/"]

# Run the app binding on port 3000
EXPOSE 3000
ENTRYPOINT ["/app/bin/monitor"]
CMD ["/app/bin/monitor", "-b", "0.0.0.0", "-p", "3000"]
