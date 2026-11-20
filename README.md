# Daimonos

Um bot para Discord escrito em **Assembly puro** (zero *runtime*, zero *garbage collector*, zero alocação dinâmica no loop principal), com binários de **~16 KB a 60 KB** e consumo residente entre **3 MB e 6 MB de RAM**.

## Arquiteturas Suportadas (5 Alvos Nativos)

| Sistema Operacional | Arquitetura | Formato | Código-Fonte |
| :--- | :--- | :--- | :--- |
| **Linux** | x86_64 | ELF64 | bot.asm (NASM) |
| **Linux** | ARM64 (AArch64) | ELF64 | bot_linux_arm64.s (GAS) |
| **Windows** | x86_64 | PE32+ | bot_win64.asm (NASM) |
| **macOS** | x86_64 (Intel) | Mach-O 64 | bot_macos.asm (NASM) |
| **macOS** | ARM64 (Apple Silicon) | Mach-O 64 | bot_macos_arm64.s (Clang/GAS) |

## Novidades e Melhorias (v2.1.0)

* **Suporte Nativo a Linux ARM64 (AArch64):** Novo port ELF64 otimizado para servidores ARM (Oracle Ampere, AWS Graviton) e Raspberry Pi, compilado e testado nativamente no CI (ubuntu-24.04-arm).
* **Reconexão Automática 24/7 (Linux x86_64):** Detecção de quedas de socket (POLLERR/POLLHUP), frames de fechamento (0x88) e eventos do Discord Gateway (Opcode 7 Reconnect / Opcode 9 Invalid Session) com limpeza TLS e reconexão automática.
* **Heartbeat Dinâmico:** Leitura em tempo real do heartbeat_interval enviado no Opcode 10 Hello, ajustando o relógio do bot ao ritmo exigido pelo servidor.
* **Segurança e Auditoria (SECURITY.md):** Verificação estrita de certificados TLS 1.3 (SSL_VERIFY_PEER), limpeza de segredos na RAM (DISCORD_TOKEN e cabeçalhos HTTP) e pilha não-executável (noexecstack, RELRO).
* **Smoke Tests Automatizados no CI:** Todos os 5 binários são compilados e executados em seus respectivos sistemas no GitHub Actions para garantir integridade da ABI antes da publicação.

## Como Usar

### Opção 1: Baixar Binário Pronto (Recomendado)
1. Acesse a aba **[Releases](../../releases)** e baixe o executável da sua plataforma junto com o SHA256SUMS.txt.
2. Valide a integridade:
```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
```
3. Defina o token e execute:
```bash
export DISCORD_TOKEN="seu_token_aqui"
./daimonos-linux-x86_64
```

### Opção 2: Compilar do Código-Fonte
Requer gcc/clang, make, openssl (libssl-dev) e nasm (para alvos x86_64):
```bash
make
DISCORD_TOKEN="seu_token_aqui" ./daimonos
```

## Segurança
Consulte [SECURITY.md](SECURITY.md) para detalhes sobre a arquitetura de segurança, builds reprodutíveis e reporte de vulnerabilidades.
