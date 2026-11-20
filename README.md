# Daimonos — Multiplatform Discord Bot in Pure x86_64 Assembly

Minimalist, zero-runtime Discord Gateway & REST bot written in **pure x86_64 NASM Assembly**, supporting **Linux (`ELF64`)**, **Windows (`Win64 / PE32+`)**, and **macOS (`Mach-O 64`)** natively.

> **Methodology:** 100% Pure Vibe Coding using **Gemini Hydrogen**.

## Build & Run

- **Linux (`ELF64`):** `make && DISCORD_TOKEN="..." ./daimonos`
- **Windows x64 (`Win64`):** `make && DISCORD_TOKEN="..." ./daimonos.exe`
- **macOS x86_64 (`Mach-O 64`):** `make && DISCORD_TOKEN="..." ./daimonos`
- **Cross-Platform Syntax Check:** `make check-all`

## License

MIT License
