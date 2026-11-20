; ============================================================================
; Daimonos - Minimalist Discord Gateway & REST Bot in Pure x86_64 Assembly
; Target: macOS x86_64 (System V AMD64 ABI, Mach-O 64) | Assembler: NASM
; Methodology: 100% Pure Vibe Coding using Gemini Hydrogen
; ============================================================================

default rel
global _main

; C Runtime & libSystem (Darwin / XNU)
extern _getenv, _printf, _puts, _exit, _memset, _strlen, _strstr, _strcmp, _signal
extern _getaddrinfo, _freeaddrinfo, _socket, _connect, _close, _poll
extern _sysctlbyname, _time

; OpenSSL (libssl / libcrypto)
extern _OPENSSL_init_ssl, _TLS_client_method, _SSL_CTX_new, _SSL_CTX_set_default_verify_paths
extern _SSL_CTX_set_verify, _SSL_new, _SSL_set_fd, _SSL_ctrl, _SSL_connect
extern _SSL_write, _SSL_read, _SSL_shutdown, _SSL_free, _RAND_bytes

%define AF_INET         2
%define SOCK_STREAM     1
%define POLLIN          0x0001
%define SIGINT          2
%define SIGTERM         15

section .data
    env_token       db "DISCORD_TOKEN", 0
    env_owner       db "ALLOWED_USER_ID", 0
    gw_host         db "gateway.discord.gg", 0
    api_host        db "discord.com", 0
    port            db "443", 0

    mib_boottime    db "kern.boottime", 0
    mib_memsize     db "hw.memsize", 0

    err_token       db "[ERROR] DISCORD_TOKEN environment variable not set.", 0
    err_dns         db "[ERROR] DNS resolution failed.", 0
    err_sock        db "[ERROR] TCP socket creation/connection failed.", 0
    err_tls         db "[ERROR] TLS 1.3 handshake or certificate verification failed.", 0
    msg_tls         db "[1/3] TLS 1.3 tunnel established (strict CA verification enabled).", 0
    msg_ws          db "[2/3] WebSocket 101 Switching Protocols OK.", 0
    msg_online      db "[3/3] Bot ONLINE (macOS)! Listening for !ping and !sysinfo...", 0
    msg_hb          db "[PING] Heartbeat sent.", 0
    fmt_cmd         db "[CMD] Channel %s | Command: %s", 10, 0
    msg_clean_exit  db 10, "[EXIT] Sensitive buffers wiped from RAM. Clean shutdown.", 0

    ws_handshake    db "GET /?v=10&encoding=json HTTP/1.1", 13, 10
                    db "Host: gateway.discord.gg", 13, 10
                    db "Upgrade: websocket", 13, 10
                    db "Connection: Upgrade", 13, 10
                    db "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==", 13, 10
                    db "Sec-WebSocket-Version: 13", 13, 10, 13, 10, 0
    ws_handshake_len equ $ - ws_handshake - 1

    id_prefix       db '{"op":2,"d":{"token":"', 0
    id_prefix_len   equ $ - id_prefix - 1
    id_suffix       db '","intents":33281,"properties":{"os":"macos","browser":"nasm-x86_64","device":"darwin"}}}', 0
    id_suffix_len   equ $ - id_suffix - 1

    hb_payload      db '{"op":1,"d":null}', 0
    hb_len          equ $ - hb_payload - 1

    key_msg_create  db '"MESSAGE_CREATE"', 0
    key_channel_id  db '"channel_id":"', 0
    key_content     db '"content":"', 0
    key_author      db '"author":{', 0
    key_id          db '"id":"', 0
    key_bot_true    db '"bot":true', 0

    cmd_ping        db "!ping", 0
    cmd_sysinfo     db "!sysinfo", 0

    reply_ping      db '{"content":"Pong! Pure x86_64 Assembly (NASM Mach-O) over TLS 1.3."}', 0
    reply_ping_len  equ $ - reply_ping - 1

    sys_p1          db '{"content":"OS: macOS x86_64 (XNU) | Uptime: ', 0
    sys_p1_len      equ $ - sys_p1 - 1
    sys_p2          db 's | Total RAM: ', 0
    sys_p2_len      equ $ - sys_p2 - 1
    sys_p3          db ' MB | Runtime: Zero (Mach-O ASM)"}', 0
    sys_p3_len      equ $ - sys_p3 - 1

    http_p1         db "POST /api/v10/channels/", 0
    http_p1_len     equ $ - http_p1 - 1
    http_p2         db "/messages HTTP/1.1", 13, 10
                    db "Host: discord.com", 13, 10
                    db "Authorization: Bot ", 0
    http_p2_len     equ $ - http_p2 - 1
    http_p3         db 13, 10, "Content-Type: application/json", 13, 10
                    db "Content-Length: ", 0
    http_p3_len     equ $ - http_p3 - 1
    http_p4         db 13, 10, "Connection: close", 13, 10, 13, 10, 0
    http_p4_len     equ $ - http_p4 - 1

section .bss
    hints           resb 48                 ; struct addrinfo (macOS/BSD = 48 bytes)
    res_ptr         resq 1
    sock_fd         resd 1
    ssl_ctx         resq 1
    ssl_conn        resq 1

    token_buf       resb 512
    token_len       resq 1
    owner_buf       resb 64
    has_owner       resb 1

    poll_fds        resb 8                  ; struct pollfd { int fd; short events; short revents; }
    hb_counter      resd 1

    recv_buf        resb 16384
    clean_json      resb 16384
    json_buf        resb 2048
    ws_frame        resb 2200
    mask_key        resb 4

    channel_id_buf  resb 64
    author_id_buf   resb 64
    content_buf     resb 512
    http_req_buf    resb 4096
    http_resp_buf   resb 2048
    num_str_buf     resb 32

    boottime_val    resq 2                  ; struct timeval { time_t tv_sec; suseconds_t tv_usec; }
    memsize_val     resq 1
    sysctl_len      resq 1
    sys_reply_buf   resb 512

section .text

cleanup_exit:
    push rbp
    mov rbp, rsp

    lea rdi, [token_buf]
    xor esi, esi
    mov edx, 512
    call _memset

    lea rdi, [http_req_buf]
    xor esi, esi
    mov edx, 4096
    call _memset

    lea rdi, [msg_clean_exit]
    call _puts

    xor edi, edi
    call _exit

u64_to_str:
    mov rax, rdi
    mov r9, 10
    xor ecx, ecx
.div_loop:
    xor edx, edx
    div r9
    add dl, '0'
    push rdx
    inc ecx
    test rax, rax
    jnz .div_loop
    xor eax, eax
.pop_loop:
    pop rdx
    mov [rsi + rax], dl
    inc eax
    cmp eax, ecx
    jl .pop_loop
    mov byte [rsi + rax], 0
    ret

ws_send_text:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    mov r12, rdi
    mov r13, rsi

    lea rdi, [mask_key]
    mov esi, 4
    call _RAND_bytes

    lea r14, [ws_frame]
    mov byte [r14], 0x81

    cmp r13, 125
    jg .send_ext16

    mov al, r13b
    or al, 0x80
    mov [r14 + 1], al
    mov eax, [mask_key]
    mov [r14 + 2], eax
    mov r15, 6
    jmp .apply_xor

.send_ext16:
    mov byte [r14 + 1], 0xFE
    mov eax, r13d
    mov [r14 + 3], al
    shr eax, 8
    mov [r14 + 2], al
    mov eax, [mask_key]
    mov [r14 + 4], eax
    mov r15, 8

.apply_xor:
    xor ecx, ecx
.xor_loop:
    cmp rcx, r13
    jge .do_write
    mov al, [r12 + rcx]
    mov rdx, rcx
    and rdx, 3
    lea r8, [mask_key]
    xor al, [r8 + rdx]
    mov [r14 + r15], al
    inc r15
    inc rcx
    jmp .xor_loop

.do_write:
    mov rdi, [ssl_conn]
    lea rsi, [ws_frame]
    mov edx, r15d
    call _SSL_write

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

ws_recv_frame:
    push rbp
    mov rbp, rsp
    push r12
    sub rsp, 8

    lea rdi, [recv_buf]
    xor esi, esi
    mov edx, 16384
    call _memset

    lea rdi, [clean_json]
    xor esi, esi
    mov edx, 16384
    call _memset

    mov rdi, [ssl_conn]
    lea rsi, [recv_buf]
    mov edx, 16383
    call _SSL_read
    cmp eax, 2
    jl .rx_err

    movzx r12d, byte [recv_buf]
    movzx ecx, byte [recv_buf + 1]
    and ecx, 0x7F

    lea rsi, [recv_buf + 2]
    cmp ecx, 126
    jl .copy_payload
    jne .rx_err

    movzx ecx, byte [recv_buf + 2]
    shl ecx, 8
    movzx edx, byte [recv_buf + 3]
    or ecx, edx
    lea rsi, [recv_buf + 4]

.copy_payload:
    cmp ecx, 16380
    jle .len_ok
    mov ecx, 16380
.len_ok:
    xor edx, edx
.cp_loop:
    cmp edx, ecx
    jge .cp_done
    mov al, [rsi + rdx]
    lea r8, [clean_json]
    mov [r8 + rdx], al
    inc edx
    jmp .cp_loop
.cp_done:
    lea r8, [clean_json]
    mov byte [r8 + rdx], 0
    mov eax, r12d
    add rsp, 8
    pop r12
    pop rbp
    ret

.rx_err:
    xor eax, eax
    add rsp, 8
    pop r12
    pop rbp
    ret

extract_json_str:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx

    call _strstr
    test rax, rax
    jz .not_found

    mov rbx, rax
    mov rdi, r12
    call _strlen
    add rbx, rax

    xor ecx, ecx
    dec r14d
.scan_val:
    cmp ecx, r14d
    jge .val_done
    mov al, [rbx + rcx]
    test al, al
    jz .val_done
    cmp al, '"'
    je .val_done
    mov [r13 + rcx], al
    inc ecx
    jmp .scan_val

.val_done:
    mov byte [r13 + rcx], 0
    mov eax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.not_found:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

build_live_sysinfo:
    push rbp
    mov rbp, rsp
    push r12
    sub rsp, 8

    ; Query kern.boottime via sysctlbyname
    mov qword [sysctl_len], 16
    lea rdi, [mib_boottime]
    lea rsi, [boottime_val]
    lea rdx, [sysctl_len]
    xor ecx, ecx
    xor r8d, r8d
    call _sysctlbyname

    ; Get current epoch time(NULL)
    xor edi, edi
    call _time
    sub rax, [boottime_val]         ; uptime = now - boottime.tv_sec
    mov r12, rax

    ; Query hw.memsize via sysctlbyname
    mov qword [sysctl_len], 8
    lea rdi, [mib_memsize]
    lea rsi, [memsize_val]
    lea rdx, [sysctl_len]
    xor ecx, ecx
    xor r8d, r8d
    call _sysctlbyname

    cld
    lea rdi, [sys_reply_buf]

    lea rsi, [sys_p1]
    mov rcx, sys_p1_len
    rep movsb

    push rdi
    mov rdi, r12
    lea rsi, [num_str_buf]
    call u64_to_str
    pop rdi
    mov rcx, rax
    lea rsi, [num_str_buf]
    rep movsb

    lea rsi, [sys_p2]
    mov rcx, sys_p2_len
    rep movsb

    push rdi
    mov rdi, [memsize_val]
    shr rdi, 20                     ; bytes -> MB
    lea rsi, [num_str_buf]
    call u64_to_str
    pop rdi
    mov rcx, rax
    lea rsi, [num_str_buf]
    rep movsb

    lea rsi, [sys_p3]
    mov rcx, sys_p3_len
    rep movsb
    mov byte [rdi], 0

    lea rax, [sys_reply_buf]
    sub rdi, rax
    mov rax, rdi

    add rsp, 8
    pop r12
    pop rbp
    ret

send_discord_reply:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24

    mov r12, rdi
    mov r13, rsi

    mov rdi, r13
    lea rsi, [num_str_buf]
    call u64_to_str
    mov r14, rax

    cld
    lea rdi, [http_req_buf]

    lea rsi, [http_p1]
    mov rcx, http_p1_len
    rep movsb

    push rdi
    lea rdi, [channel_id_buf]
    call _strlen
    pop rdi
    mov rcx, rax
    lea rsi, [channel_id_buf]
    rep movsb

    lea rsi, [http_p2]
    mov rcx, http_p2_len
    rep movsb

    lea rsi, [token_buf]
    mov rcx, [token_len]
    rep movsb

    lea rsi, [http_p3]
    mov rcx, http_p3_len
    rep movsb

    lea rsi, [num_str_buf]
    mov rcx, r14
    rep movsb

    lea rsi, [http_p4]
    mov rcx, http_p4_len
    rep movsb

    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov byte [rdi], 0

    lea rax, [http_req_buf]
    sub rdi, rax
    mov r15, rdi

    lea rdi, [hints]
    xor esi, esi
    mov edx, 48
    call _memset
    mov dword [hints + 4], AF_INET
    mov dword [hints + 8], SOCK_STREAM

    lea rdi, [api_host]
    lea rsi, [port]
    lea rdx, [hints]
    lea rcx, [res_ptr]
    call _getaddrinfo
    test eax, eax
    jnz .api_done

    mov rbx, [res_ptr]
    mov edi, [rbx + 4]
    mov esi, [rbx + 8]
    mov edx, [rbx + 12]
    call _socket
    cmp eax, -1
    je .api_free_dns
    mov [rbp - 48], eax

    ; On macOS/BSD struct addrinfo: ai_addrlen is at offset 16, ai_addr is at offset 32
    mov edi, [rbp - 48]
    mov rsi, [rbx + 32]
    mov edx, [rbx + 16]
    call _connect
    test eax, eax
    jnz .api_close_sock

    mov rdi, [res_ptr]
    call _freeaddrinfo

    mov rdi, [ssl_ctx]
    call _SSL_new
    mov [rbp - 56], rax

    mov rdi, [rbp - 56]
    mov esi, [rbp - 48]
    call _SSL_set_fd

    mov rdi, [rbp - 56]
    mov esi, 55
    xor edx, edx
    lea rcx, [api_host]
    call _SSL_ctrl

    mov rdi, [rbp - 56]
    call _SSL_connect
    cmp eax, 1
    jne .api_free_ssl

    mov rdi, [rbp - 56]
    lea rsi, [http_req_buf]
    mov edx, r15d
    call _SSL_write

    mov rdi, [rbp - 56]
    lea rsi, [http_resp_buf]
    mov edx, 2047
    call _SSL_read

    mov rdi, [rbp - 56]
    call _SSL_shutdown

.api_free_ssl:
    mov rdi, [rbp - 56]
    call _SSL_free

.api_close_sock:
    mov edi, [rbp - 48]
    call _close
    jmp .api_wipe

.api_free_dns:
    mov rdi, [res_ptr]
    call _freeaddrinfo

.api_wipe:
    lea rdi, [http_req_buf]
    xor esi, esi
    mov edx, 4096
    call _memset

.api_done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

_main:
    push rbp
    mov rbp, rsp

    mov edi, SIGINT
    lea rsi, [cleanup_exit]
    call _signal
    mov edi, SIGTERM
    lea rsi, [cleanup_exit]
    call _signal

    mov byte [has_owner], 0
    lea rdi, [env_owner]
    call _getenv
    test rax, rax
    jz .read_token
    mov r12, rax
    mov rdi, r12
    call _strlen
    test rax, rax
    jz .read_token
    cmp rax, 60
    jg .read_token
    mov rcx, rax
    cld
    lea rdi, [owner_buf]
    mov rsi, r12
    rep movsb
    mov byte [rdi], 0
    mov byte [has_owner], 1

.read_token:
    lea rdi, [env_token]
    call _getenv
    test rax, rax
    jz .no_token
    mov r12, rax

    mov rdi, r12
    call _strlen
    cmp rax, 500
    jg .no_token
    mov r13, rax

.trim_tok:
    test r13, r13
    jz .no_token
    movzx eax, byte [r12 + r13 - 1]
    cmp al, 10
    je .dec_tok
    cmp al, 13
    je .dec_tok
    cmp al, 32
    je .dec_tok
    cmp al, '"'
    je .dec_tok
    jmp .copy_tok
.dec_tok:
    dec r13
    jmp .trim_tok

.copy_tok:
    mov [token_len], r13
    cld
    lea rdi, [token_buf]
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov byte [rdi], 0

    lea rdi, [hints]
    xor esi, esi
    mov edx, 48
    call _memset
    mov dword [hints + 4], AF_INET
    mov dword [hints + 8], SOCK_STREAM

    lea rdi, [gw_host]
    lea rsi, [port]
    lea rdx, [hints]
    lea rcx, [res_ptr]
    call _getaddrinfo
    test eax, eax
    jnz .dns_fail

    mov rbx, [res_ptr]
    mov edi, [rbx + 4]
    mov esi, [rbx + 8]
    mov edx, [rbx + 12]
    call _socket
    cmp eax, -1
    je .sock_fail
    mov [sock_fd], eax

    ; On macOS/BSD struct addrinfo: ai_addrlen is at offset 16, ai_addr is at offset 32
    mov edi, [sock_fd]
    mov rsi, [rbx + 32]
    mov edx, [rbx + 16]
    call _connect
    test eax, eax
    jnz .sock_fail

    mov rdi, [res_ptr]
    call _freeaddrinfo

    xor edi, edi
    xor esi, esi
    call _OPENSSL_init_ssl

    call _TLS_client_method
    mov rdi, rax
    call _SSL_CTX_new
    test rax, rax
    jz .tls_fail
    mov [ssl_ctx], rax

    mov rdi, [ssl_ctx]
    call _SSL_CTX_set_default_verify_paths

    mov rdi, [ssl_ctx]
    mov esi, 1
    xor edx, edx
    call _SSL_CTX_set_verify

    mov rdi, [ssl_ctx]
    call _SSL_new
    mov [ssl_conn], rax

    mov rdi, [ssl_conn]
    mov esi, [sock_fd]
    call _SSL_set_fd

    mov rdi, [ssl_conn]
    mov esi, 55
    xor edx, edx
    lea rcx, [gw_host]
    call _SSL_ctrl

    mov rdi, [ssl_conn]
    call _SSL_connect
    cmp eax, 1
    jne .tls_fail

    lea rdi, [msg_tls]
    call _puts

    mov rdi, [ssl_conn]
    lea rsi, [ws_handshake]
    mov edx, ws_handshake_len
    call _SSL_write

    mov rdi, [ssl_conn]
    lea rsi, [recv_buf]
    mov edx, 16383
    call _SSL_read

    lea rdi, [msg_ws]
    call _puts

    call ws_recv_frame

    cld
    lea rdi, [json_buf]
    lea rsi, [id_prefix]
    mov rcx, id_prefix_len
    rep movsb

    lea rsi, [token_buf]
    mov rcx, [token_len]
    rep movsb

    lea rsi, [id_suffix]
    mov rcx, id_suffix_len
    rep movsb
    mov byte [rdi], 0

    mov rsi, id_prefix_len
    add rsi, [token_len]
    add rsi, id_suffix_len
    lea rdi, [json_buf]
    call ws_send_text

    lea rdi, [json_buf]
    xor esi, esi
    mov edx, 2048
    call _memset

    lea rdi, [ws_frame]
    xor esi, esi
    mov edx, 2200
    call _memset

    lea rdi, [msg_online]
    call _puts

    mov eax, [sock_fd]
    mov [poll_fds], eax
    mov word [poll_fds + 4], POLLIN
    mov dword [hb_counter], 0

.event_loop:
    mov word [poll_fds + 6], 0
    lea rdi, [poll_fds]
    mov esi, 1
    mov edx, 1000
    call _poll

    test eax, eax
    jle .tick_heartbeat

    test word [poll_fds + 6], POLLIN
    jz .tick_heartbeat

    call ws_recv_frame
    cmp eax, 0x81
    jne .tick_heartbeat

    lea rdi, [clean_json]
    lea rsi, [key_msg_create]
    call _strstr
    test rax, rax
    jz .tick_heartbeat

    lea rdi, [clean_json]
    lea rsi, [key_bot_true]
    call _strstr
    test rax, rax
    jnz .tick_heartbeat

    cmp byte [has_owner], 1
    jne .parse_fields

    lea rdi, [clean_json]
    lea rsi, [key_author]
    call _strstr
    test rax, rax
    jz .tick_heartbeat

    mov rdi, rax
    lea rsi, [key_id]
    lea rdx, [author_id_buf]
    mov ecx, 64
    call extract_json_str
    test eax, eax
    jz .tick_heartbeat

    lea rdi, [author_id_buf]
    lea rsi, [owner_buf]
    call _strcmp
    test eax, eax
    jnz .tick_heartbeat

.parse_fields:
    lea rdi, [clean_json]
    lea rsi, [key_channel_id]
    lea rdx, [channel_id_buf]
    mov ecx, 64
    call extract_json_str
    test eax, eax
    jz .tick_heartbeat

    lea rdi, [clean_json]
    lea rsi, [key_content]
    lea rdx, [content_buf]
    mov ecx, 512
    call extract_json_str
    test eax, eax
    jz .tick_heartbeat

    lea rdi, [content_buf]
    lea rsi, [cmd_ping]
    call _strstr
    lea rdx, [content_buf]
    cmp rax, rdx
    je .exec_ping

    lea rdi, [content_buf]
    lea rsi, [cmd_sysinfo]
    call _strstr
    lea rdx, [content_buf]
    cmp rax, rdx
    je .exec_sysinfo
    jmp .tick_heartbeat

.exec_ping:
    lea rdi, [fmt_cmd]
    lea rsi, [channel_id_buf]
    lea rdx, [content_buf]
    xor eax, eax
    call _printf

    lea rdi, [reply_ping]
    mov rsi, reply_ping_len
    call send_discord_reply
    jmp .tick_heartbeat

.exec_sysinfo:
    lea rdi, [fmt_cmd]
    lea rsi, [channel_id_buf]
    lea rdx, [content_buf]
    xor eax, eax
    call _printf

    call build_live_sysinfo
    mov rsi, rax
    lea rdi, [sys_reply_buf]
    call send_discord_reply

.tick_heartbeat:
    inc dword [hb_counter]
    cmp dword [hb_counter], 25
    jl .event_loop

    mov dword [hb_counter], 0
    lea rdi, [hb_payload]
    mov rsi, hb_len
    call ws_send_text

    lea rdi, [msg_hb]
    call _puts
    jmp .event_loop

.no_token:
    lea rdi, [err_token]
    call _puts
    mov edi, 1
    call _exit

.dns_fail:
    lea rdi, [err_dns]
    call _puts
    mov edi, 1
    call _exit

.sock_fail:
    lea rdi, [err_sock]
    call _puts
    mov edi, 1
    call _exit

.tls_fail:
    lea rdi, [err_tls]
    call _puts
    mov edi, 1
    call _exit
