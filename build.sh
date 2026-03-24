#!/bin/bash
# =============================================================
# AmneziaWG builder for ASUS GT-AX11000 (Merlin 388.11)
# =============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ROUTER_IP="${1:-}"

# --- Step 1: Get kernel config from router ---
if [ ! -f kernel.config ]; then
    if [ -z "$ROUTER_IP" ]; then
        echo "kernel.config not found."
        echo ""
        echo "Usage:"
        echo "  ./build.sh <router-ip>        # auto-extract config via SSH"
        echo "  ./build.sh                     # if kernel.config already exists"
        echo ""
        echo "Or extract manually on the router:"
        echo "  cat /proc/config.gz | gunzip > /tmp/kernel.config"
        echo "  scp admin@<router>:/tmp/kernel.config ."
        exit 1
    fi

    echo "[1/3] Extracting kernel config from router ${ROUTER_IP}..."
    ssh "admin@${ROUTER_IP}" 'cat /proc/config.gz' | gunzip > kernel.config
    echo "      Saved kernel.config ($(wc -l < kernel.config) lines)"
else
    echo "[1/3] Using existing kernel.config"
fi

# Verify config
if ! grep -q "CONFIG_WIREGUARD=m" kernel.config; then
    echo "WARNING: CONFIG_WIREGUARD=m not found in kernel.config"
    echo "         The config may be incorrect"
fi

# --- Step 2: Docker build ---
echo "[2/3] Building amneziawg.ko + awg (this may take 10-30 min on first run)..."
echo ""

DOCKER_BUILDKIT=1 docker build --output=./output .

# --- Step 3: Verify ---
echo ""
echo "[3/3] Build complete!"
echo ""
echo "Artifacts:"
ls -lh output/
echo ""
echo "Module vermagic:"
strings output/amneziawg.ko | grep "vermagic="
echo ""
echo "=== Next steps ==="
echo "  scp output/amneziawg.ko output/awg admin@${ROUTER_IP:-<router-ip>}:/tmp/"
echo "  scp install.sh admin@${ROUTER_IP:-<router-ip>}:/tmp/"
echo "  ssh admin@${ROUTER_IP:-<router-ip>}"
echo "  sh /tmp/install.sh"
