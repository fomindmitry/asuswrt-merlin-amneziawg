# =============================================================
# AmneziaWG-Go Generic Builder
# =============================================================
ARG GO_IMAGE_VERSION=1.24
FROM --platform=linux/amd64 golang:${GO_IMAGE_VERSION}-alpine AS builder

RUN apk add --no-cache git make

# Build arguments
ARG AWG_GO_VERSION=v0.2.18
ARG TARGET_OS=linux
ARG TARGET_ARCH=arm
ARG TARGET_ARM=7

WORKDIR /build

# Clone specific version or branch
RUN git clone --depth 1 --branch ${AWG_GO_VERSION} \
    https://github.com/amnezia-vpn/amneziawg-go.git

# Patch PreallocatedBuffersPerPool and queue sizes to avoid OOM on limited memory devices
# Default in v0.2.18 is 0 (unbounded).
# 1024 is the standard WireGuard-Go limit, but here we enforce it to prevent infinite growth.
RUN cd amneziawg-go && \
    sed -i 's/PreallocatedBuffersPerPool = 0/PreallocatedBuffersPerPool = 1024/' device/queueconstants_default.go && \
    sed -i 's/QueueOutboundSize = 1024/QueueOutboundSize = 1024/' device/queueconstants_default.go && \
    sed -i 's/QueueInboundSize = 1024/QueueInboundSize = 1024/' device/queueconstants_default.go && \
    sed -i 's/QueueHandshakeSize = 1024/QueueHandshakeSize = 1024/' device/queueconstants_default.go

# Build binary
RUN cd amneziawg-go && \
    GOOS=${TARGET_OS} GOARCH=${TARGET_ARCH} GOARM=${TARGET_ARM} \
    go build -v -ldflags="-s -w" -o /output/amneziawg-go

FROM scratch AS export
COPY --from=builder /output/ /
