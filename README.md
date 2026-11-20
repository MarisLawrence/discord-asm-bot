# Daimonos — Discord Bot in Pure x86_64 Assembly

Minimalist, zero-runtime Discord Gateway & REST bot written in **x86_64 NASM Assembly** for Linux, linking directly against OpenSSL (`libssl` / `libcrypto`) and invoking raw Linux kernel syscalls.

> **Pure Vibe Coding Experiment:** 100% of the source code, protocol framing, memory hardening, and debugging in this repository were generated purely through **Vibe Coding using Gemini Hydrogen**, with zero manual Assembly boilerplate written beforehand.

## Architecture & Highlights

- **RFC 6455 WebSocket Framing in Registers:** Custom frame encoder/decoder handling 7-bit and 16-bit Big-Endian payload lengths with 32-bit XOR masking powered by OpenSSL CSPRNG (`RAND_bytes`).
- **TLS 1.3 with Strict Certificate Verification:** Connects to `gateway.discord.gg:443` and `discord.com:443` with SNI (`SSL_ctrl`) and `SSL_VERIFY_PEER` enabled against system CA certificates.
- **Multiplexed Event Loop:** Uses `poll()` (1000 ms timeout) to process real-time `MESSAGE_CREATE` dispatch events while maintaining the Gateway Heartbeat cycle.
- **Direct Linux Kernel Syscalls:** Executes `SYS_uname` (`63`) and `SYS_sysinfo` (`99`) directly via `syscall` instructions to report live kernel release, CPU architecture, uptime, and free RAM.
- **Memory & Binary Hardening:**
  - Non-executable stack (`-z noexecstack`), full RELRO (`-z relro -z now`), and stripped symbols (`~16 KB` final ELF binary).
  - Automatic zeroing (`memset`) of serialized payload buffers and signal handlers (`SIGINT`/`SIGTERM`) to wipe `DISCORD_TOKEN` from RAM on exit.
  - Optional `ALLOWED_USER_ID` environment variable to restrict command execution to a single Discord user ID.

## Requirements

- Linux `x86_64`
- `nasm`
- `gcc`
- `openssl` (`libssl`, `libcrypto`)

## Build & Run

    make
    DISCORD_TOKEN="your_bot_token" ./daimonos

Optional owner lock:

    DISCORD_TOKEN="your_bot_token" ALLOWED_USER_ID="your_discord_user_id" ./daimonos

## Supported Commands

- `!ping` — Verifies WebSocket Gateway reception and HTTPS REST API reply path.
- `!sysinfo` — Queries the host Linux kernel directly via syscalls and posts live kernel version, architecture, uptime, and free RAM.
