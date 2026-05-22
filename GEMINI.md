# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AmneziaWG userspace daemon + web UI addon for ASUS routers running Asuswrt-Merlin 388.x/3006.x firmware. Provides DPI-obfuscated WireGuard VPN with per-device policy routing and GeoIP/GeoSite selective routing.

**Targets:**
- **ARM64 (aarch64):** GT-AX11000, RT-AX86U, RT-AX88U Pro, etc. (HND platform, Kernel 4.1.51+)
- **ARMv7 (armhf):** RT-AX5400, RT-AX58U, etc. (Kernel 4.19+)

## Build

```bash
# Build amneziawg-go (userspace) via Docker
./build-go.sh                 # default: arm v7
./build-go.sh v0.2.18 arm64   # for 64-bit routers

# Build awg CLI tool
./build.sh                    # ARM64
DOCKER_BUILDKIT=1 docker build -f Dockerfile.arm32 --output=output . # ARMv7
```

## Architecture

### Userspace vs Kernel Module
While an AmneziaWG kernel module is available, this project defaults to **`amneziawg-go` (userspace)** for maximum compatibility.
- **Why:** The kernel module conflicts with the ASUS "Flow Control" (Hardware Acceleration) feature on many models, leading to system instability or bypass of VPN routing.
- **Automated FlowCache Management:** If the kernel module (`amneziawg.ko`) is used, the script automatically executes `fc disable` during startup and `fc enable` during stop to maintain stability.
- **Fallback Mechanism:** The backend attempts to load the kernel module first if present; if it fails to load or create the interface, it gracefully falls back to the userspace `amneziawg-go` daemon.

### Memory & Performance Optimizations (Critical)

Low-RAM routers (512MB) require specific tuning:
- **Bounded Pools:** `amneziawg-go` is patched in `Dockerfile.go` to set `PreallocatedBuffersPerPool = 1024`. Default `0` leads to unbounded OOM.
- **Queue Sizes:** Internal queues (Inbound/Outbound/Handshake) must be maintained at **1024**. Reducing these to 256 or 512 (to save RAM) causes protocol deadlocks and handshake loops on the RT-AX5400.
- **Go Runtime:** Started with `GOMEMLIMIT=320MiB` and `GOGC=20` to keep heap usage minimal.
- **Vectorized Pipelines:** 
  - **GeoSite Extraction:** Uses a single-pass `awk` pipeline (`extract_v2fly_domains`) to parse the 20MB+ v2fly domain database, writing multiple category files simultaneously. This is ~10x faster than traditional grep/sed loops.
  - **Ipset Loading:** Utilizes `ipset restore` for bulk loading CIDR lists, reducing firewall setup time from minutes to seconds.
  - **Dnsmasq Batching:** Domains are batched (`build_dnsmasq_config`, 20 per line) into `dnsmasq` configuration to minimize process overhead.
- **Resolution Parallelism:** Domain pre-resolution utilizes parallel `nslookup` tasks with a batch size of **50** to populate the `ipset` rapidly during the synchronous startup sequence.

### Routing & Security Model

- **Policy Routing:** Three policies per device: `vpn_all` (table 300), `vpn_geo` (ipset match + table 300), or `direct`.
- **DNS Interception:** When VPN is active, the script forces all LAN DNS traffic (port 53) to the router's `dnsmasq` and rejects outgoing DoH (port 443) to known providers. This ensures GeoSite domain-based routing is never bypassed by client-side DNS settings.
- **IPv6 Leak Protection:** Automatically injects `ip6tables` REJECT rules when the tunnel is active to prevent traffic leaking via IPv6 if the ISP provides it.
- **Resilient Watchdog:** The 5-minute watchdog checks connectivity via pings. If pings fail, it verifies the **Handshake Age**; if a handshake occurred within the last 3 minutes, it avoids a redundant restart. To prevent maintenance tasks from wiping out scheduled jobs, `do_start` and `setup_firewall` default to `init_cron` for initial provisioning, while maintenance and restart routines (like the watchdog) explicitly pass a `keep_cron` flag to preserve existing cron scheduling.
- **Health Check & Rollback:** On startup, the script performs a 60-second connectivity test. To prevent race conditions, a global execution lock is held throughout the entire **Start → Verify → Rollback** sequence. If the tunnel fails to pass traffic, it automatically rolls back firewall changes and stops the daemon using a `no_lock` bypass to prevent deadlocks.
- **Atomic Locking:** All service actions (start, stop, restart, watchdog) are synchronized via a `/tmp/.awg_lock` directory. The lock duration is specifically extended to cover the asynchronous health check loop, preventing overlapping execution attempts from multiple sources (e.g., manual UI action + cron watchdog).
- **Synchronous Initialization:** Core firewall setup and domain resolution remain synchronous to ensure routing tables and `ipset` entries are fully populated before the tunnel is verified. UI polling (90 attempts / 3 mins) accounts for this processing time.

### Logging & Observability

- **System Logger:** All logs are dispatched via `log_msg` to the system syslog (`logger -t amneziawg`).
- **Daemon Logs:** `amneziawg-go` output is captured in `/tmp/awg_daemon.log` to assist in diagnosing startup failures or crash loops.
- **Conventions:** 
  - **ERROR:** Prefixed with `ERROR:` for critical failures (e.g., config missing, daemon crash).
  - **WARNING:** Prefixed with `WARNING:` for non-fatal issues (e.g., ipset full, geo download failed).
  - **INFO:** Plain text for lifecycle events and status changes.
- **Lifecycle Traceability:** The `do_start`, `do_stop`, and `setup_firewall` functions provide a granular trace of operations (e.g., config generation, TUN preparation, ipset creation, route injection). This allows for deep troubleshooting of VPN startup sequences directly from the router's system log.
- **Connectivity Monitoring:** The health check loop logs its progress and failure reasons to aid in diagnosing endpoint reachability or obfuscation parameter issues.

### Testing & Quality Assurance

- **Modular Logic:** Core parsing and configuration building are isolated into standalone functions within `amneziawg.sh`.
- **Unit Testing:** The script includes a `test_mode` case, allowing unit tests (see `tests/`) to source functions directly without triggering router-modifying service actions.
- **Regression Suite:** 
  - `tests/test_optimized_functions.sh`: Verifies performance optimizations (awk pipelines, dnsmasq batching).
  - `tests/test_validation.sh`: Enforces strict type checking for obfuscation parameters.
- **Parameter Validation Rules:**
  - **Signed 32-bit Integers:** `Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `S3`, `S4`.
  - **Unsigned 32-bit (Range Support):** `H1`, `H2`, `H3`, `H4` (supports single values or `start-end` ranges).

**Best Practices for VPN Geo:**
- **GeoIP (IP-based):** Best for messaging apps (Telegram) or services with stable IP ranges (Cloudflare, Microsoft). Avoid overly broad ranges like "google" unless necessary.
- **GeoSite (Domain-based):** Preferred for massive CDNs (YouTube, TikTok, Netflix) or developer services (category-dev, github). Precise and memory-efficient.

### Build pipeline (`Dockerfile`)
Multi-stage Docker build: downloads Merlin toolchain + kernel source, applies router's kernel config, builds out-of-tree AmneziaWG kernel module and userspace tools from upstream repos. Uses `docker build --output` to export artifacts.

### Router-side components

**`addon/amneziawg.sh`** — Main backend script (runs on router). Handles:
- **Interface Lifecycle:** `start`/`stop`/`restart` (insmod/rmmod, ip link, awg setconf, iptables, ip rule).
- **Config Generation:** Reads from `custom_settings.txt`. Obfuscation parameters `I1-I5` are stored individually (e.g., `awg_i1`) to bypass single-variable length limits in Merlin's storage, supporting long strings (up to 2048 chars).
- **Per-device Routing Policy:** Managed via `vpn_all`, `vpn_geo`, or `direct` policies using `iptables` mangle marks and `ip rule` priority levels.
- **GeoIP/GeoSite:** Dynamic GeoIP downloading (based on `awg_geo_v2fly_ip`) and vectorized GeoSite extraction. Populates `ipset` (`awg_dst`) and generates `dnsmasq` ipset rules.
- **Service Event Dispatch:** Integrated with Merlin's `service-event` and `wan-event` hooks for automatic lifecycle management.

**`addon/amneziawg_page.asp`** — Web UI page (ROG-styled ASP). Communicates with backend via Merlin's `httpApi` and service events. Features:
- **Case-insensitive Importer:** Supports standard WireGuard/AmneziaWG `.conf` files (handles both `i1` and `I1` keys).
- **Autocomplete:** Integrated autocomplete for v2fly GeoSite categories and GeoIP services.
- **Live Status:** Real-time monitoring of tunnel traffic, handshake age, and active routing rules.

**`install.sh`** — One-shot installer (runs on router via SSH). Copies files, tests environment compatibility, creates init scripts, and installs the Web UI addon.

### Key paths on router
- `/opt/amneziawg/` — binaries (`awg`, `amneziawg-go`), kernel module (`amneziawg.ko`), config, and geo data.
- `/jffs/addons/amneziawg/` — addon script and ASP page.
- `/jffs/configs/dnsmasq.conf.add` — domain-based routing rules (tagged with `### AmneziaWG`).
- `/jffs/addons/custom_settings.txt` — Merlin settings store (all keys prefixed `awg_`).

### Routing model
- **Table 300:** Dedicated routing table for VPN traffic.
- **FWMARK 0x100:** Used to tag traffic for GeoIP/GeoSite matching.
- **Priority Rules:**
  - `prio 97`: Direct traffic (exclusions).
  - `prio 98`: Marked traffic (GeoIP/GeoSite) -> Table 300.
  - `prio 99`: VPN-all traffic -> Table 300.
  - `prio 100`: Router-originated traffic (optional).

## Shell scripting notes

All router-side scripts must be POSIX sh (busybox ash) — no bashisms. The router runs BusyBox with limited coreutils.
