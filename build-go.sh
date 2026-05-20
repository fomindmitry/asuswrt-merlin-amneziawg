# =============================================================
# Build AmneziaWG-Go (Generic)
# Usage: ./build-go.sh [version] [arch] [arm_ver]
# Example: ./build-go.sh v0.2.18 arm 7
#          ./build-go.sh v0.2.18 arm64
# =============================================================
set -e

VERSION="${1:-v0.2.18}"
ARCH="${2:-arm}"
ARM_VER="${3:-7}"

echo "Building amneziawg-go ${VERSION} for ${ARCH} (ARM v${ARM_VER})..."

DOCKER_BUILDKIT=1 docker build \
    -f Dockerfile.go \
    --build-arg AWG_GO_VERSION="${VERSION}" \
    --build-arg TARGET_ARCH="${ARCH}" \
    --build-arg TARGET_ARM="${ARM_VER}" \
    --output=./output .

# Rename output to include version/arch for clarity
BIN_NAME="amneziawg-go-${VERSION}-${ARCH}v${ARM_VER}"
[ "${ARCH}" == "arm64" ] && BIN_NAME="amneziawg-go-${VERSION}-arm64"

mv output/amneziawg-go "output/${BIN_NAME}"

echo ""
echo "Build complete!"
ls -lh "output/${BIN_NAME}"
echo ""
echo "To use on router:"
echo "  scp output/${BIN_NAME} admin@<router-ip>:/opt/amneziawg/amneziawg-go"
echo "  ssh admin@<router-ip> chmod +x /opt/amneziawg/amneziawg-go"
