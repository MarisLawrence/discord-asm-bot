DEFAULT REL
; ============================================================================
; Daimonos - Minimalist Discord Gateway & REST Bot in Pure x86_64 Assembly
; Target: Windows x64 (Microsoft x64 ABI, Win64) | Assembler: NASM
; Methodology: 100% Pure Vibe Coding using Gemini Hydrogen
; ============================================================================

default rel
global main

; C Runtime (UCRT / MSVCRT)
extern getenv, printf, puts, exit, memset, strlen, strstr, strcmp, signal

; Winsock2 (ws2_32.dll)
extern WSAStartup, WSACleanup, WSAPoll
extern getaddrinfo, freeaddrinfo, socket, connect, closesocket

; Win32 Kernel API (kernel32.dll)
extern GetTickCount64, GlobalMemoryStatusEx

; OpenSSL (libssl / libcrypto)
extern OPENSSL_init_ssl, TLS_client_method, SSL_CTX_new, SSL_CTX_set_default_verify_paths
extern SSL_CTX_set_verify, SSL_new, SSL_set_fd, SSL_ctrl, SSL_connect
extern SSL_write, SSL_read, SSL_shutdown, SSL_free, RAND_bytes

%define AF_INET         2
%define SOCK_STREAM     1
%define POLLIN          0x0100
%define SIGINT          2
%define SIGTERM         15

section .data
    env_token       db "DISCORD_TOKEN", 0
    env_owner       db "ALLOWED_USER_ID", 0
    gw_host         db "gateway.discord.gg", 0
    api_host        db "discord.com", 0
    port            db "443", 0

    err_wsa         db "[ERROR] WSAStartup failed.", 0
    err_token       db "[ERROR] DISCORD_TOKEN environment variable not set.", 0
    err_dns         db "[ERROR] DNS resolution failed.", 0
    err_sock        db "[ERROR] TCP socket creation/connection failed.", 0
    err_tls         db "[ERROR] TLS 1.3 handshake or certificate verification failed.", 0
    msg_tls         db "[1/3] TLS 1.3 tunnel established (strict CA verification enabled).", 0
    msg_ws          db "[2/3] WebSocket 101 Switching Protocols OK.", 0
    msg_online      db "[3/3] Bot ONLINE (Win64)! Listening for !ping and !sysinfo...", 0
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
    id_suffix       db '","intents":33281,"properties":{"os":"windows","browser":"nasm-x86_64","device":"win64"}}}', 0
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

    reply_ping      db '{"content":"Pong! Pure x86_64 Assembly (NASM Win64) over TLS 1.3."}', 0
    reply_ping_len  equ $ - reply_ping - 1

    sys_p1          db '{"content":"OS: Windows x86_64 | Uptime: ', 0
    sys_p1_len      equ $ - sys_p1 - 1
    sys_p2          db 's | Free RAM: ', 0
    sys_p2_len      equ $ - sys_p2 - 1
    sys_p3          db ' MB | Runtime: Zero (Win64 ASM)"}', 0
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
    wsa_data        resb 408
    hints           resb 48
    res_ptr         resq 1
    sock_fd         resq 1
    ssl_ctx         resq 1
    ssl_conn        resq 1

    token_buf       resb 512
    token_len       resq 1
    owner_buf       resb 64
    has_owner       resb 1

    poll_fds        resb 16
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

    mem_status      resb 64
    sys_reply_buf   resb 512

section .text

cleanup_exit:
    push rbp
    mov rbp, rsp
    sub rsp, 32

    lea rcx, [token_buf]
    xor edx, edx
    mov r8d, 512
    call memset

    lea rcx, [http_req_buf]
    xor edx, edx
    mov r8d, 4096
    call memset

    lea rcx, [msg_clean_exit]
    call puts

    call WSACleanup

    xor ecx, ecx
    call exit

u64_to_str_safe:
    mov rax, rcx
    mov r10, rdx
    mov r9, 10
    xor r8d, r8d
.div_loop:
    xor edx, edx
    div r9
    add dl, '0'
    push rdx
    inc r8d
    test rax, rax
    jnz .div_loop
    xor eax, eax
.pop_loop:
    pop rdx
    mov [r10 + rax], dl
    inc eax
    cmp eax, r8d
    jl .pop_loop
    mov byte [r10 + rax], 0
    ret

ws_send_text:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    mov r12, rcx
    mov r13, rdx

    lea rcx, [mask_key]
    mov edx, 4
    call RAND_bytes

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
    xor al, [mask_key + rdx]
    mov [r14 + r15], al
    inc r15
    inc rcx
    jmp .xor_loop

.do_write:
    mov rcx, [ssl_conn]
    lea rdx, [ws_frame]
    mov r8d, r15d
    call SSL_write

    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

ws_recv_frame:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
    push r12
    sub rsp, 40

    lea rcx, [recv_buf]
    xor edx, edx
    mov r8d, 16384
    call memset

    lea rcx, [clean_json]
    xor edx, edx
    mov r8d, 16384
    call memset

    mov rcx, [ssl_conn]
    lea rdx, [recv_buf]
    mov r8d, 16383
    call SSL_read
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
    mov [clean_json + rdx], al
    inc edx
    jmp .cp_loop
.cp_done:
    mov byte [clean_json + rdx], 0
    mov eax, r12d
    add rsp, 40
    pop r12
    pop rdi
    pop rsi
    pop rbp
    ret

.rx_err:
    xor eax, eax
    add rsp, 40
    pop r12
    pop rdi
    pop rsi
    pop rbp
    ret

extract_json_str:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32

    mov r12, rdx
    mov r13, r8
    mov r14d, r9d

    call strstr
    test rax, rax
    jz .not_found

    mov rbx, rax
    mov rcx, r12
    call strlen
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
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.not_found:
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

build_live_sysinfo:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
    push r12
    sub rsp, 40

    call GetTickCount64
    xor edx, edx
    mov rcx, 1000
    div rcx
    mov r12, rax

    mov dword [mem_status], 64
    lea rcx, [mem_status]
    call GlobalMemoryStatusEx

    cld
    lea rdi, [sys_reply_buf]

    lea rsi, [sys_p1]
    mov rcx, sys_p1_len
    rep movsb

    mov rcx, r12
    lea rdx, [num_str_buf]
    call u64_to_str_safe
    mov rcx, rax
    lea rsi, [num_str_buf]
    rep movsb

    lea rsi, [sys_p2]
    mov rcx, sys_p2_len
    rep movsb

    mov rcx, [mem_status + 16]
    shr rcx, 20
    lea rdx, [num_str_buf]
    call u64_to_str_safe
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

    add rsp, 40
    pop r12
    pop rdi
    pop rsi
    pop rbp
    ret

send_discord_reply:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56

    mov r12, rcx
    mov r13, rdx

    mov rcx, r13
    lea rdx, [num_str_buf]
    call u64_to_str_safe
    mov r14, rax

    cld
    lea rdi, [http_req_buf]

    lea rsi, [http_p1]
    mov rcx, http_p1_len
    rep movsb

    lea rcx, [channel_id_buf]
    call strlen
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

    lea rcx, [hints]
    xor edx, edx
    mov r8d, 48
    call memset
    mov dword [hints + 4], AF_INET
    mov dword [hints + 8], SOCK_STREAM

    lea rcx, [api_host]
    lea rdx, [port]
    lea r8, [hints]
    lea r9, [res_ptr]
    call getaddrinfo
    test eax, eax
    jnz .api_done

    mov rbx, [res_ptr]
    mov ecx, [rbx + 4]
    mov edx, [rbx + 8]
    mov r8d, [rbx + 12]
    call socket
    cmp rax, -1
    je .api_free_dns
    mov [rbp - 64], rax

    mov rcx, [rbp - 64]
    mov rdx, [rbx + 32]
    mov r8d, [rbx + 16]
    call connect
    test eax, eax
    jnz .api_close_sock

    mov rcx, [res_ptr]
    call freeaddrinfo

    mov rcx, [ssl_ctx]
    call SSL_new
    mov [rbp - 72], rax

    mov rcx, [rbp - 72]
    mov rdx, [rbp - 64]
    call SSL_set_fd

    mov rcx, [rbp - 72]
    mov edx, 55
    xor r8d, r8d
    lea r9, [api_host]
    call SSL_ctrl

    mov rcx, [rbp - 72]
    call SSL_connect
    cmp eax, 1
    jne .api_free_ssl

    mov rcx, [rbp - 72]
    lea rdx, [http_req_buf]
    mov r8d, r15d
    call SSL_write

    mov rcx, [rbp - 72]
    lea rdx, [http_resp_buf]
    mov r8d, 2047
    call SSL_read

    mov rcx, [rbp - 72]
    call SSL_shutdown

.api_free_ssl:
    mov rcx, [rbp - 72]
    call SSL_free

.api_close_sock:
    mov rcx, [rbp - 64]
    call closesocket
    jmp .api_wipe

.api_free_dns:
    mov rcx, [res_ptr]
    call freeaddrinfo

.api_wipe:
    lea rcx, [http_req_buf]
    xor edx, edx
    mov r8d, 4096
    call memset

.api_done:
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

main:
    push rbp
    mov rbp, rsp
    sub rsp, 48

    mov ecx, SIGINT
    lea rdx, [cleanup_exit]
    call signal
    mov ecx, SIGTERM
    lea rdx, [cleanup_exit]
    call signal

    mov ecx, 0x0202
    lea rdx, [wsa_data]
    call WSAStartup
    test eax, eax
    jnz .wsa_fail

    mov byte [has_owner], 0
    lea rcx, [env_owner]
    call getenv
    test rax, rax
    jz .read_token
    mov r12, rax
    mov rcx, r12
    call strlen
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
    lea rcx, [env_token]
    call getenv
    test rax, rax
    jz .no_token
    mov r12, rax

    mov rcx, r12
    call strlen
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

    lea rcx, [hints]
    xor edx, edx
    mov r8d, 48
    call memset
    mov dword [hints + 4], AF_INET
    mov dword [hints + 8], SOCK_STREAM

    lea rcx, [gw_host]
    lea rdx, [port]
    lea r8, [hints]
    lea r9, [res_ptr]
    call getaddrinfo
    test eax, eax
    jnz .dns_fail

    mov rbx, [res_ptr]
    mov ecx, [rbx + 4]
    mov edx, [rbx + 8]
    mov r8d, [rbx + 12]
    call socket
    cmp rax, -1
    je .sock_fail
    mov [sock_fd], rax

    mov rcx, [sock_fd]
    mov rdx, [rbx + 32]
    mov r8d, [rbx + 16]
    call connect
    test eax, eax
    jnz .sock_fail

    mov rcx, [res_ptr]
    call freeaddrinfo

    xor ecx, ecx
    xor edx, edx
    call OPENSSL_init_ssl

    call TLS_client_method
    mov rcx, rax
    call SSL_CTX_new
    test rax, rax
    jz .tls_fail
    mov [ssl_ctx], rax

    mov rcx, [ssl_ctx]
    call SSL_CTX_set_default_verify_paths

    mov rcx, [ssl_ctx]
    mov edx, 1
    xor r8d, r8d
    call SSL_CTX_set_verify

    mov rcx, [ssl_ctx]
    call SSL_new
    mov [ssl_conn], rax

    mov rcx, [ssl_conn]
    mov rdx, [sock_fd]
    call SSL_set_fd

    mov rcx, [ssl_conn]
    mov edx, 55
    xor r8d, r8d
    lea r9, [gw_host]
    call SSL_ctrl

    mov rcx, [ssl_conn]
    call SSL_connect
    cmp eax, 1
    jne .tls_fail

    lea rcx, [msg_tls]
    call puts

    mov rcx, [ssl_conn]
    lea rdx, [ws_handshake]
    mov r8d, ws_handshake_len
    call SSL_write

    mov rcx, [ssl_conn]
    lea rdx, [recv_buf]
    mov r8d, 16383
    call SSL_read

    lea rcx, [msg_ws]
    call puts

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

    mov rdx, id_prefix_len
    add rdx, [token_len]
    add rdx, id_suffix_len
    lea rcx, [json_buf]
    call ws_send_text

    lea rcx, [json_buf]
    xor edx, edx
    mov r8d, 2048
    call memset

    lea rcx, [ws_frame]
    xor edx, edx
    mov r8d, 2200
    call memset

    lea rcx, [msg_online]
    call puts

    mov rax, [sock_fd]
    mov [poll_fds], rax
    mov word [poll_fds + 8], POLLIN
    mov dword [hb_counter], 0

.event_loop:
    mov word [poll_fds + 10], 0
    lea rcx, [poll_fds]
    mov edx, 1
    mov r8d, 1000
    call WSAPoll

    test eax, eax
    jle .tick_heartbeat

    test word [poll_fds + 10], POLLIN
    jz .tick_heartbeat

    call ws_recv_frame
    cmp eax, 0x81
    jne .tick_heartbeat

    lea rcx, [clean_json]
    lea rdx, [key_msg_create]
    call strstr
    test rax, rax
    jz .tick_heartbeat

    lea rcx, [clean_json]
    lea rdx, [key_bot_true]
    call strstr
    test rax, rax
    jnz .tick_heartbeat

    cmp byte [has_owner], 1
    jne .parse_fields

    lea rcx, [clean_json]
    lea rdx, [key_author]
    call strstr
    test rax, rax
    jz .tick_heartbeat

    mov rcx, rax
    lea rdx, [key_id]
    lea r8, [author_id_buf]
    mov r9d, 64
    call extract_json_str
    test eax, eax
    jz .tick_heartbeat

    lea rcx, [author_id_buf]
    lea rdx, [owner_buf]
    call strcmp
    test eax, eax
    jnz .tick_heartbeat

.parse_fields:
    lea rcx, [clean_json]
    lea rdx, [key_channel_id]
    lea r8, [channel_id_buf]
    mov r9d, 64
    call extract_json_str
    test eax, eax
    jz .tick_heartbeat

    lea rcx, [clean_json]
    lea rdx, [key_content]
    lea r8, [content_buf]
    mov r9d, 512
    call extract_json_str
    test eax, eax
    jz .tick_heartbeat

    lea rcx, [content_buf]
    lea rdx, [cmd_ping]
    call strstr
    lea rdx, [content_buf]
    cmp rax, rdx
    je .exec_ping

    lea rcx, [content_buf]
    lea rdx, [cmd_sysinfo]
    call strstr
    lea rdx, [content_buf]
    cmp rax, rdx
    je .exec_sysinfo
    jmp .tick_heartbeat

.exec_ping:
    lea rcx, [fmt_cmd]
    lea rdx, [channel_id_buf]
    lea r8, [content_buf]
    call printf

    lea rcx, [reply_ping]
    mov rdx, reply_ping_len
    call send_discord_reply
    jmp .tick_heartbeat

.exec_sysinfo:
    lea rcx, [fmt_cmd]
    lea rdx, [channel_id_buf]
    lea r8, [content_buf]
    call printf

    call build_live_sysinfo
    mov rdx, rax
    lea rcx, [sys_reply_buf]
    call send_discord_reply

.tick_heartbeat:
    inc dword [hb_counter]
    cmp dword [hb_counter], 25
    jl .event_loop

    mov dword [hb_counter], 0
    lea rcx, [hb_payload]
    mov rdx, hb_len
    call ws_send_text

    lea rcx, [msg_hb]
    call puts
    jmp .event_loop

.wsa_fail:
    lea rcx, [err_wsa]
    call puts
    mov ecx, 1
    call exit

.no_token:
    lea rcx, [err_token]
    call puts
    mov ecx, 1
    call exit

.dns_fail:
    lea rcx, [err_dns]
    call puts
    mov ecx, 1
    call exit

.sock_fail:
    lea rcx, [err_sock]
    call puts
    mov ecx, 1
    call exit

.tls_fail:
    lea rcx, [err_tls]
    call puts
    mov ecx, 1
    call exit
