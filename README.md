# Daimonos — Multiplatform Discord Bot in Pure Assembly

Minimalist, zero-runtime Discord Gateway & REST bot written in **pure Assembly**, natively supporting **4 architectures and operating systems** without any high-level runtime, garbage collector, or wrapper libraries.

> **Methodology:** 100% Pure Vibe Coding using **Gemini Hydrogen**.

---

## Supported Architectures & Platforms

| Target Platform | Architecture | Source File | Assembler & Format | Calling Convention (ABI) | System Telemetry (`!sysinfo`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Linux** | `x86_64` | `bot.asm` | NASM (`ELF64`) | System V AMD64 ABI | Direct kernel `syscall` (`SYS_uname`, `SYS_sysinfo`) |
| **Windows** | `x86_64` | `bot_win64.asm` | NASM (`Win64 / PE32+`) | Microsoft x64 ABI | Win32 `GetTickCount64` & `GlobalMemoryStatusEx` |
| **macOS (Intel)** | `x86_64` | `bot_macos.asm` | NASM (`Mach-O 64`) | System V AMD64 ABI | Darwin `sysctlbyname` (`kern.boottime`, `hw.memsize`) |
| **macOS (Apple Silicon)** | `ARM64 / AArch64` | `bot_macos_arm64.s` | Apple Clang / GAS (`Mach-O`) | Apple ARM64 ABI | Darwin `sysctlbyname` (`kern.boottime`, `hw.memsize`) |

### Core Architecture
- **TLS 1.3 & Strict Certificate Verification:** Links directly against OpenSSL (`libssl` / `libcrypto`) with SNI (`SSL_ctrl`) and default CA trust store validation (`SSL_CTX_set_default_verify_paths`).
- **Custom RFC 6455 WebSocket Engine:** Handcrafted binary frame encoder/decoder with `RAND_bytes` 32-bit XOR payload masking and 16-bit extended length framing.
- **Zero-Allocation JSON Scanner:** In-place string extraction (`strstr` + `strlen` pointer arithmetic) for `MESSAGE_CREATE` dispatch events, `!ping`, and `!sysinfo`.
- **Hardened Memory Hygiene:** Zeroes sensitive token and HTTP `Authorization` buffers in RAM upon `SIGINT` / `SIGTERM` or after REST API calls.

---

## Build & Run

The unified `Makefile` automatically detects your OS and CPU architecture (`uname -s` / `uname -m`):

```bash
make
```

- **Linux (`x86_64`):** `make && DISCORD_TOKEN="your_token" ./daimonos`
- **Windows (`x64` via MSYS2 MinGW64):** `make && DISCORD_TOKEN="your_token" ./daimonos.exe`
- **macOS (`Intel x86_64` & `Apple Silicon ARM64`):** `brew install nasm openssl@3 && make && DISCORD_TOKEN="your_token" ./daimonos`

### Optional Owner Lock
Restrict command execution (`!ping`, `!sysinfo`) to a single Discord User ID:
```bash
export ALLOWED_USER_ID="123456789012345678"
```

---

## License

Released under the [MIT License](LICENSE).
