# Security Policy

## Supported Versions

| Version | Supported |
| :--- | :--- |
| v2.x | :white_check_mark: |

## Security Architecture
- **Strict TLS 1.3:** Verifies peer certificates against the OS default CA store (`SSL_VERIFY_PEER`).
- **Memory Hygiene:** Sensitive `DISCORD_TOKEN` and HTTP `Authorization` buffers are zeroed in RAM on exit (`SIGINT`/`SIGTERM`) and after REST calls.
- **Static Buffers:** Zero dynamic heap allocation (`malloc`/`free`) in the main event loop.
- **Reproducible Builds:** Official release binaries are built exclusively via public GitHub Actions runners with `SHA256SUMS.txt`.

## Reporting a Vulnerability
Please open a **Private Security Advisory** under the repository **Security** tab instead of a public issue.
