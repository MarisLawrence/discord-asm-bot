# ============================================================================
# Daimonos — Multiplatform Makefile (Linux ELF64 | Windows Win64 | macOS Mach-O)
# ============================================================================

NASM     ?= nasm
CC       ?= gcc
TARGET   ?= daimonos

# Auto-detect OS
ifeq ($(OS),Windows_NT)
    PLATFORM := windows
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
        PLATFORM := linux
    else ifeq ($(UNAME_S),Darwin)
        PLATFORM := macos
    else
        $(error Unsupported OS: $(UNAME_S))
    endif
endif

# Platform-specific flags
ifeq ($(PLATFORM),linux)
    SRC      := bot.asm
    OBJ      := bot.o
    OUT      := $(TARGET)
    ASMFLAGS := -f elf64
    LDFLAGS  := -lssl -lcrypto -no-pie -Wl,-z,noexecstack,-z,relro,-z,now
    STRIP    := strip --strip-all $(OUT)
else ifeq ($(PLATFORM),windows)
    SRC      := bot_win64.asm
    OBJ      := bot_win64.obj
    OUT      := $(TARGET).exe
    ASMFLAGS := -f win64
    LDFLAGS  := -lssl -lcrypto -lws2_32 -lkernel32
    STRIP    := strip --strip-all $(OUT)
else ifeq ($(PLATFORM),macos)
    UNAME_M  := $(shell uname -m)
    OUT      := $(TARGET)
    BREW_SSL := $(shell brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)
    LDFLAGS  := -L$(BREW_SSL)/lib -lssl -lcrypto
    STRIP    := strip -x $(OUT)
    ifeq ($(UNAME_M),arm64)
        SRC  := bot_macos_arm64.s
        OBJ  := bot_macos_arm64.o
    else
        SRC  := bot_macos.asm
        OBJ  := bot_macos.o
        ASMFLAGS := -f macho64
    endif
endif

.PHONY: all clean check-all

all: $(OUT)

$(OUT): $(SRC)
	$(if $(filter %.s,$(SRC)),$(CC) -arch arm64 -c $(SRC) -o $(OBJ),$(NASM) $(ASMFLAGS) $(SRC) -o $(OBJ))
	$(CC) $(OBJ) -o $(OUT) $(LDFLAGS)
	$(STRIP)

# Validate assembly syntax across all 3 platforms locally
check-all:
	$(NASM) -f elf64 bot.asm -o bot.o
	$(NASM) -f win64 bot_win64.asm -o bot_win64.obj
	$(NASM) -f macho64 bot_macos.asm -o bot_macos.o
	rm -f bot.o bot_win64.obj bot_macos.o
	@echo "[OK] Linux (elf64), Windows (win64) & macOS (macho64) assembled cleanly."

clean:
	rm -f bot.o bot_win64.obj bot_macos.o $(TARGET) $(TARGET).exe
