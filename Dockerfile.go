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

# Build binary
RUN cd amneziawg-go && \
    GOOS=${TARGET_OS} GOARCH=${TARGET_ARCH} GOARM=${TARGET_ARM} \
    go build -v -ldflags="-s -w" -o /output/amneziawg-go

FROM scratch AS export
COPY --from=builder /output/ /
