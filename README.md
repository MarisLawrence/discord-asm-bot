# Daimonos

A Discord bot written in **pure Assembly** (zero runtime, zero garbage collector, zero dynamic heap allocation in the main event loop), producing **~16 KB to 60 KB** binaries with **3 MB to 6 MB** resident memory usage.

## Supported Platforms (5 Native Targets)

| Operating System | Architectures | Format | Source Files |
| :--- | :--- | :--- | :--- |
| **Linux** | x86_64, ARM64 (AArch64) | ELF64 | bot.asm (NASM), bot_linux_arm64.s (GAS) |
| **Windows** | x86_64 | PE32+ | bot_win64.asm (NASM) |
| **macOS** | x86_64 (Intel), ARM64 (Apple Silicon) | Mach-O 64 | bot_macos.asm (NASM), bot_macos_arm64.s (Clang/GAS) |

## What is New (v2.1.0)

* **Native Linux ARM64 (AArch64) Support:** New ELF64 port targeting ARM servers (Oracle Ampere, AWS Graviton) and Raspberry Pi, natively built and tested in CI (ubuntu-24.04-arm).
* **24/7 Auto-Reconnect (Linux x86_64):** Detects socket drops (POLLERR/POLLHUP), WebSocket close frames (0x88), and Discord Gateway events (Opcode 7 Reconnect / Opcode 9 Invalid Session) with clean TLS teardown and automatic reconnection.
* **Dynamic Heartbeat:** Parses heartbeat_interval in real time from Opcode 10 Hello, syncing the bot clock directly to the server requirement.
* **Security & Auditing (SECURITY.md):** Strict TLS 1.3 certificate verification (SSL_VERIFY_PEER), RAM secret wiping (DISCORD_TOKEN and HTTP headers), and non-executable stack hardening (noexecstack, RELRO).
* **Automated CI Smoke Tests:** All 5 binaries are compiled and executed on their respective native runners in GitHub Actions to verify ABI integrity before release.

## Usage

### Option 1: Download Prebuilt Binary (Recommended)
1. Go to the **[Releases](../../releases)** tab and download the binary for your platform along with SHA256SUMS.txt.
2. Verify integrity:
```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
```
3. Export your token and run:
```bash
export DISCORD_TOKEN="your_token_here"
./daimonos-linux-x86_64
```

### Option 2: Build from Source
Requires gcc/clang, make, openssl (libssl-dev), and nasm (for x86_64 targets):
```bash
make
DISCORD_TOKEN="your_token_here" ./daimonos
```


## Development
Built purely through **vibecoding** using **Gemini Hydrogen** and **Neon**.

## Security
See [SECURITY.md](SECURITY.md) for details on the security architecture, reproducible builds, and vulnerability reporting.

## Author & License
Created and architected by **[MarisLawrence](https://github.com/MarisLawrence)** (built purely through **vibecoding** using **Gemini Hydrogen** and **Neon**).

Licensed under the [MIT License](LICENSE).
