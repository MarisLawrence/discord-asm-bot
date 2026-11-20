ASM      = nasm
ASMFLAGS = -f elf64
CC       = gcc
LDFLAGS  = -lssl -lcrypto -Wl,-z,noexecstack,-z,relro,-z,now
TARGET   = daimonos

.PHONY: all clean

all: $(TARGET)

$(TARGET): bot.o
	$(CC) bot.o -o $(TARGET) $(LDFLAGS)
	strip --strip-all $(TARGET)

bot.o: bot.asm
	$(ASM) $(ASMFLAGS) bot.asm -o bot.o

clean:
	rm -f bot.o bot $(TARGET)
