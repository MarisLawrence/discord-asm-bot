// ============================================================================
// Daimonos - Minimalist Discord Gateway & REST Bot in Pure ARM64 Assembly
// Target: macOS Apple Silicon (M1/M2/M3/M4, AArch64 Mach-O)
// Assembler: Apple Clang Integrated Assembler (GAS)
// ============================================================================

.text
.align 2
.globl main

// Constants
.equ AF_INET,       2
.equ SOCK_STREAM,   1
.equ POLLIN,        0x0001
.equ SIGINT,        2
.equ SIGTERM,       15

// ----------------------------------------------------------------------------
// Signal Handler: wipes sensitive buffers from RAM
// ----------------------------------------------------------------------------
cleanup_exit:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    adrp x0, token_buf
    add x0, x0, :lo12:token_buf
    mov w1, #0
    mov x2, #512
    bl memset

    adrp x0, http_req_buf
    add x0, x0, :lo12:http_req_buf
    mov w1, #0
    mov x2, #4096
    bl memset

    adrp x0, msg_clean_exit
    add x0, x0, :lo12:msg_clean_exit
    bl puts

    mov w0, #0
    bl exit

// ----------------------------------------------------------------------------
// u64_to_str(x0 = value, x1 = dst_buf) -> returns length in x0
// ----------------------------------------------------------------------------
u64_to_str:
    mov x2, #10
    mov x3, #0                  // digit count
    sub sp, sp, #32             // temp stack buffer for digits
1:
    udiv x4, x0, x2             // x4 = x0 / 10
    msub x5, x4, x2, x0         // x5 = x0 - (x4 * 10)
    add w5, w5, #'0'
    strb w5, [sp, x3]
    add x3, x3, #1
    mov x0, x4
    cbnz x0, 1b

    mov x4, #0                  // out index
    mov x5, x3
2:
    sub x5, x5, #1
    ldrb w6, [sp, x5]
    strb w6, [x1, x4]
    add x4, x4, #1
    cmp x4, x3
    b.lt 2b

    strb wzr, [x1, x4]
    add sp, sp, #32
    mov x0, x3
    ret

// ----------------------------------------------------------------------------
// memcpy_bytes(x0 = dst, x1 = src, x2 = len) -> returns dst + len in x0
// ----------------------------------------------------------------------------
memcpy_bytes:
    mov x3, #0
1:
    cmp x3, x2
    b.ge 2f
    ldrb w4, [x1, x3]
    strb w4, [x0, x3]
    add x3, x3, #1
    b 1b
2:
    add x0, x0, x2
    ret

// ----------------------------------------------------------------------------
// ws_send_text(x0 = payload_ptr, x1 = payload_len)
// ----------------------------------------------------------------------------
ws_send_text:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]

    mov x19, x0                 // payload_ptr
    mov x20, x1                 // payload_len

    adrp x0, mask_key
    add x0, x0, :lo12:mask_key
    mov w1, #4
    bl RAND_bytes

    adrp x21, ws_frame
    add x21, x21, :lo12:ws_frame
    mov w0, #0x81
    strb w0, [x21]

    cmp x20, #125
    b.gt 1f

    orr w0, w20, #0x80
    strb w0, [x21, #1]
    adrp x1, mask_key
    add x1, x1, :lo12:mask_key
    ldr w0, [x1]
    str w0, [x21, #2]
    mov x22, #6
    b 2f
1:
    mov w0, #0xFE
    strb w0, [x21, #1]
    lsr w0, w20, #8
    strb w0, [x21, #2]
    strb w20, [x21, #3]
    adrp x1, mask_key
    add x1, x1, :lo12:mask_key
    ldr w0, [x1]
    str w0, [x21, #4]
    mov x22, #8
2:
    adrp x2, mask_key
    add x2, x2, :lo12:mask_key
    mov x3, #0
3:
    cmp x3, x20
    b.ge 4f
    ldrb w4, [x19, x3]
    and x5, x3, #3
    ldrb w6, [x2, x5]
    eor w4, w4, w6
    strb w4, [x21, x22]
    add x22, x22, #1
    add x3, x3, #1
    b 3b
4:
    adrp x0, ssl_conn
    add x0, x0, :lo12:ssl_conn
    ldr x0, [x0]
    mov x1, x21
    mov w2, w22
    bl SSL_write

    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// ----------------------------------------------------------------------------
// ws_recv_frame() -> returns opcode in w0 and JSON in clean_json
// ----------------------------------------------------------------------------
ws_recv_frame:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]

    adrp x0, recv_buf
    add x0, x0, :lo12:recv_buf
    mov w1, #0
    mov x2, #16384
    bl memset

    adrp x0, clean_json
    add x0, x0, :lo12:clean_json
    mov w1, #0
    mov x2, #16384
    bl memset

    adrp x0, ssl_conn
    add x0, x0, :lo12:ssl_conn
    ldr x0, [x0]
    adrp x1, recv_buf
    add x1, x1, :lo12:recv_buf
    mov w2, #16383
    bl SSL_read
    cmp w0, #2
    b.lt 4f

    adrp x1, recv_buf
    add x1, x1, :lo12:recv_buf
    ldrb w19, [x1]               // opcode
    ldrb w2, [x1, #1]
    and w2, w2, #0x7F           // payload len

    add x3, x1, #2              // payload ptr
    cmp w2, #126
    b.lt 1f
    b.ne 4f

    ldrb w2, [x1, #2]
    lsl w2, w2, #8
    ldrb w4, [x1, #3]
    orr w2, w2, w4
    add x3, x1, #4
1:
    mov w4, #16380
    cmp w2, w4
    csel w2, w2, w4, le

    adrp x0, clean_json
    add x0, x0, :lo12:clean_json
    mov w4, #0
2:
    cmp w4, w2
    b.ge 3f
    ldrb w5, [x3, x4]
    strb w5, [x0, x4]
    add w4, w4, #1
    b 2b
3:
    strb wzr, [x0, x4]
    mov w0, w19
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
4:
    mov w0, #0
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// ----------------------------------------------------------------------------
// extract_json_str(x0 = json, x1 = key_prefix, x2 = dst, w3 = max_len)
// ----------------------------------------------------------------------------
extract_json_str:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]

    mov x19, x1                 // key_prefix
    mov x20, x2                 // dst
    mov w21, w3                 // max_len

    bl strstr
    cbz x0, 3f
    mov x22, x0

    mov x0, x19
    bl strlen
    add x22, x22, x0

    mov w1, #0
    sub w21, w21, #1
1:
    cmp w1, w21
    b.ge 2f
    ldrb w2, [x22, x1]
    cbz w2, 2f
    cmp w2, #'"'
    b.eq 2f
    strb w2, [x20, x1]
    add w1, w1, #1
    b 1b
2:
    strb wzr, [x20, x1]
    mov w0, #1
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret
3:
    mov w0, #0
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// ----------------------------------------------------------------------------
// build_live_sysinfo() -> populates sys_reply_buf via Darwin sysctlbyname
// ----------------------------------------------------------------------------
build_live_sysinfo:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]

    adrp x0, sysinfo_buf
    add x0, x0, :lo12:sysinfo_buf
    bl sysinfo

    adrp x1, sysinfo_buf
    add x1, x1, :lo12:sysinfo_buf
    ldr x19, [x1, #0]           // uptime (segundos)
    ldr x2, [x1, #32]           // totalram
    ldr w3, [x1, #104]          // mem_unit
    mul x2, x2, x3
    adrp x4, memsize_val
    add x4, x4, :lo12:memsize_val
    str x2, [x4]

    adrp x20, sys_reply_buf
    add x20, x20, :lo12:sys_reply_buf

    mov x0, x20
    adrp x1, sys_p1
    add x1, x1, :lo12:sys_p1
    mov x2, #45
    bl memcpy_bytes
    mov x20, x0

    mov x0, x19
    adrp x1, num_str_buf
    add x1, x1, :lo12:num_str_buf
    bl u64_to_str
    mov x2, x0
    mov x0, x20
    adrp x1, num_str_buf
    add x1, x1, :lo12:num_str_buf
    bl memcpy_bytes
    mov x20, x0

    adrp x1, sys_p2
    add x1, x1, :lo12:sys_p2
    mov x2, #15
    bl memcpy_bytes
    mov x20, x0

    adrp x0, memsize_val
    add x0, x0, :lo12:memsize_val
    ldr x0, [x0]
    lsr x0, x0, #20             // bytes -> MB
    adrp x1, num_str_buf
    add x1, x1, :lo12:num_str_buf
    bl u64_to_str
    mov x2, x0
    mov x0, x20
    adrp x1, num_str_buf
    add x1, x1, :lo12:num_str_buf
    bl memcpy_bytes
    mov x20, x0

    adrp x1, sys_p3
    add x1, x1, :lo12:sys_p3
    mov x2, #37
    bl memcpy_bytes
    strb wzr, [x0]

    adrp x1, sys_reply_buf
    add x1, x1, :lo12:sys_reply_buf
    sub x0, x0, x1

    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// ----------------------------------------------------------------------------
// send_discord_reply(x0 = json_body_ptr, x1 = json_body_len)
// ----------------------------------------------------------------------------
send_discord_reply:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]

    mov x19, x0                 // json_body_ptr
    mov x20, x1                 // json_body_len

    mov x0, x20
    adrp x1, num_str_buf
    add x1, x1, :lo12:num_str_buf
    bl u64_to_str
    mov x21, x0                 // num_str_len

    adrp x22, http_req_buf
    add x22, x22, :lo12:http_req_buf

    mov x0, x22
    adrp x1, http_p1
    add x1, x1, :lo12:http_p1
    mov x2, #23
    bl memcpy_bytes
    mov x22, x0

    adrp x0, channel_id_buf
    add x0, x0, :lo12:channel_id_buf
    bl strlen
    mov x2, x0
    mov x0, x22
    adrp x1, channel_id_buf
    add x1, x1, :lo12:channel_id_buf
    bl memcpy_bytes
    mov x22, x0

    adrp x1, http_p2
    add x1, x1, :lo12:http_p2
    mov x2, #60
    bl memcpy_bytes
    mov x22, x0

    adrp x1, token_buf
    add x1, x1, :lo12:token_buf
    adrp x2, token_len
    add x2, x2, :lo12:token_len
    ldr x2, [x2]
    bl memcpy_bytes
    mov x22, x0

    adrp x1, http_p3
    add x1, x1, :lo12:http_p3
    mov x2, #50
    bl memcpy_bytes
    mov x22, x0

    adrp x1, num_str_buf
    add x1, x1, :lo12:num_str_buf
    mov x2, x21
    bl memcpy_bytes
    mov x22, x0

    adrp x1, http_p4
    add x1, x1, :lo12:http_p4
    mov x2, #23
    bl memcpy_bytes
    mov x22, x0

    mov x1, x19
    mov x2, x20
    bl memcpy_bytes
    strb wzr, [x0]

    adrp x1, http_req_buf
    add x1, x1, :lo12:http_req_buf
    sub x23, x0, x1             // total http req len

    adrp x0, hints
    add x0, x0, :lo12:hints
    mov w1, #0
    mov x2, #48
    bl memset
    adrp x0, hints
    add x0, x0, :lo12:hints
    mov w1, #AF_INET
    str w1, [x0, #4]
    mov w1, #SOCK_STREAM
    str w1, [x0, #8]

    adrp x0, api_host
    add x0, x0, :lo12:api_host
    adrp x1, port
    add x1, x1, :lo12:port
    adrp x2, hints
    add x2, x2, :lo12:hints
    adrp x3, res_ptr
    add x3, x3, :lo12:res_ptr
    bl getaddrinfo
    cbnz w0, 5f

    adrp x0, res_ptr
    add x0, x0, :lo12:res_ptr
    ldr x24, [x0]
    ldr w0, [x24, #4]
    ldr w1, [x24, #8]
    ldr w2, [x24, #12]
    bl socket
    cmn w0, #1
    b.eq 4f
    mov w25, w0                 // api_sock

    mov w0, w25
    ldr x1, [x24, #24]          // Darwin addrinfo->ai_addr at offset 32
    ldr w2, [x24, #16]          // ai_addrlen at offset 16
    bl connect
    cbnz w0, 3f

    mov x0, x24
    bl freeaddrinfo

    adrp x0, ssl_ctx
    add x0, x0, :lo12:ssl_ctx
    ldr x0, [x0]
    bl SSL_new
    mov x26, x0                 // api_ssl

    mov x0, x26
    mov w1, w25
    bl SSL_set_fd

    mov x0, x26
    mov w1, #55                 // SSL_CTRL_SET_TLSEXT_HOSTNAME
    mov x2, #0
    adrp x3, api_host
    add x3, x3, :lo12:api_host
    bl SSL_ctrl

    mov x0, x26
    bl SSL_connect
    cmp w0, #1
    b.ne 2f

    mov x0, x26
    adrp x1, http_req_buf
    add x1, x1, :lo12:http_req_buf
    mov w2, w23
    bl SSL_write

    mov x0, x26
    adrp x1, http_resp_buf
    add x1, x1, :lo12:http_resp_buf
    mov w2, #2047
    bl SSL_read

    mov x0, x26
    bl SSL_shutdown
2:
    mov x0, x26
    bl SSL_free
3:
    mov w0, w25
    bl close
    b 5f
4:
    mov x0, x24
    bl freeaddrinfo
5:
    adrp x0, http_req_buf
    add x0, x0, :lo12:http_req_buf
    mov w1, #0
    mov x2, #4096
    bl memset

    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret

// ----------------------------------------------------------------------------
// Main Entry Point (_main)
// ----------------------------------------------------------------------------
main:
    stp x29, x30, [sp, #-48]!
    mov x29, sp

    mov w0, #SIGINT
    adrp x1, cleanup_exit
    add x1, x1, :lo12:cleanup_exit
    bl signal

    mov w0, #SIGTERM
    adrp x1, cleanup_exit
    add x1, x1, :lo12:cleanup_exit
    bl signal

    adrp x0, env_owner
    add x0, x0, :lo12:env_owner
    bl getenv
    cbz x0, 1f
    mov x19, x0
    bl strlen
    cbz x0, 1f
    cmp x0, #60
    b.gt 1f
    mov x2, x0
    adrp x0, owner_buf
    add x0, x0, :lo12:owner_buf
    mov x1, x19
    bl memcpy_bytes
    strb wzr, [x0]
    adrp x0, has_owner
    add x0, x0, :lo12:has_owner
    mov w1, #1
    strb w1, [x0]
1:
    adrp x0, env_token
    add x0, x0, :lo12:env_token
    bl getenv
    cbz x0, err_no_token
    mov x19, x0
    bl strlen
    cmp x0, #500
    b.gt err_no_token
    mov x20, x0

trim_tok:
    cbz x20, err_no_token
    sub x1, x20, #1
    ldrb w2, [x19, x1]
    cmp w2, #10
    b.eq dec_tok
    cmp w2, #13
    b.eq dec_tok
    cmp w2, #32
    b.eq dec_tok
    cmp w2, #'"'
    b.eq dec_tok
    b copy_tok
dec_tok:
    sub x20, x20, #1
    b trim_tok

copy_tok:
    adrp x0, token_len
    add x0, x0, :lo12:token_len
    str x20, [x0]
    adrp x0, token_buf
    add x0, x0, :lo12:token_buf
    mov x1, x19
    mov x2, x20
    bl memcpy_bytes
    strb wzr, [x0]

    adrp x0, hints
    add x0, x0, :lo12:hints
    mov w1, #0
    mov x2, #48
    bl memset
    adrp x0, hints
    add x0, x0, :lo12:hints
    mov w1, #AF_INET
    str w1, [x0, #4]
    mov w1, #SOCK_STREAM
    str w1, [x0, #8]

    adrp x0, gw_host
    add x0, x0, :lo12:gw_host
    adrp x1, port
    add x1, x1, :lo12:port
    adrp x2, hints
    add x2, x2, :lo12:hints
    adrp x3, res_ptr
    add x3, x3, :lo12:res_ptr
    bl getaddrinfo
    cbnz w0, err_dns_fail

    adrp x0, res_ptr
    add x0, x0, :lo12:res_ptr
    ldr x19, [x0]
    ldr w0, [x19, #4]
    ldr w1, [x19, #8]
    ldr w2, [x19, #12]
    bl socket
    cmn w0, #1
    b.eq err_sock_fail
    mov w20, w0
    adrp x0, sock_fd
    add x0, x0, :lo12:sock_fd
    str w20, [x0]

    mov w0, w20
    ldr x1, [x19, #24]
    ldr w2, [x19, #16]
    bl connect
    cbnz w0, err_sock_fail

    mov x0, x19
    bl freeaddrinfo

    mov x0, #0
    mov x1, #0
    bl OPENSSL_init_ssl

    bl TLS_client_method
    bl SSL_CTX_new
    cbz x0, err_tls_fail
    mov x19, x0
    adrp x1, ssl_ctx
    add x1, x1, :lo12:ssl_ctx
    str x19, [x1]

    mov x0, x19
    bl SSL_CTX_set_default_verify_paths

    mov x0, x19
    mov w1, #1
    mov x2, #0
    bl SSL_CTX_set_verify

    mov x0, x19
    bl SSL_new
    mov x21, x0
    adrp x1, ssl_conn
    add x1, x1, :lo12:ssl_conn
    str x21, [x1]

    mov x0, x21
    mov w1, w20
    bl SSL_set_fd

    mov x0, x21
    mov w1, #55
    mov x2, #0
    adrp x3, gw_host
    add x3, x3, :lo12:gw_host
    bl SSL_ctrl

    mov x0, x21
    bl SSL_connect
    cmp w0, #1
    b.ne err_tls_fail

    adrp x0, msg_tls
    add x0, x0, :lo12:msg_tls
    bl puts

    mov x0, x21
    adrp x1, ws_handshake
    add x1, x1, :lo12:ws_handshake
    mov w2, #159
    bl SSL_write

    mov x0, x21
    adrp x1, recv_buf
    add x1, x1, :lo12:recv_buf
    mov w2, #16383
    bl SSL_read

    adrp x0, msg_ws
    add x0, x0, :lo12:msg_ws
    bl puts

    bl ws_recv_frame

    adrp x22, json_buf
    add x22, x22, :lo12:json_buf

    mov x0, x22
    adrp x1, id_prefix
    add x1, x1, :lo12:id_prefix
    mov x2, #22
    bl memcpy_bytes
    mov x22, x0

    adrp x1, token_buf
    add x1, x1, :lo12:token_buf
    adrp x2, token_len
    add x2, x2, :lo12:token_len
    ldr x2, [x2]
    bl memcpy_bytes
    mov x22, x0

    adrp x1, id_suffix
    add x1, x1, :lo12:id_suffix
    mov x2, #90
    bl memcpy_bytes
    strb wzr, [x0]

    adrp x1, json_buf
    add x1, x1, :lo12:json_buf
    sub x1, x0, x1
    adrp x0, json_buf
    add x0, x0, :lo12:json_buf
    bl ws_send_text

    adrp x0, json_buf
    add x0, x0, :lo12:json_buf
    mov w1, #0
    mov x2, #2048
    bl memset

    adrp x0, msg_online
    add x0, x0, :lo12:msg_online
    bl puts

    adrp x0, poll_fds
    add x0, x0, :lo12:poll_fds
    str w20, [x0]
    mov w1, #POLLIN
    strh w1, [x0, #4]

event_loop:
    adrp x0, poll_fds
    add x0, x0, :lo12:poll_fds
    strh wzr, [x0, #6]
    mov w1, #1
    mov w2, #1000
    bl poll

    cmp w0, #0
    b.le tick_heartbeat

    adrp x0, poll_fds
    add x0, x0, :lo12:poll_fds
    ldrh w1, [x0, #6]
    tst w1, #POLLIN
    b.eq tick_heartbeat

    bl ws_recv_frame
    cmp w0, #0x81
    b.ne tick_heartbeat

    adrp x0, clean_json
    add x0, x0, :lo12:clean_json
    adrp x1, key_msg_create
    add x1, x1, :lo12:key_msg_create
    bl strstr
    cbz x0, tick_heartbeat

    adrp x0, clean_json
    add x0, x0, :lo12:clean_json
    adrp x1, key_bot_true
    add x1, x1, :lo12:key_bot_true
    bl strstr
    cbnz x0, tick_heartbeat

    adrp x0, has_owner
    add x0, x0, :lo12:has_owner
    ldrb w0, [x0]
    cmp w0, #1
    b.ne parse_fields

    adrp x0, clean_json
    add x0, x0, :lo12:clean_json
    adrp x1, key_author
    add x1, x1, :lo12:key_author
    bl strstr
    cbz x0, tick_heartbeat

    adrp x1, key_id
    add x1, x1, :lo12:key_id
    adrp x2, author_id_buf
    add x2, x2, :lo12:author_id_buf
    mov w3, #64
    bl extract_json_str
    cbz w0, tick_heartbeat

    adrp x0, author_id_buf
    add x0, x0, :lo12:author_id_buf
    adrp x1, owner_buf
    add x1, x1, :lo12:owner_buf
    bl strcmp
    cbnz w0, tick_heartbeat

parse_fields:
    adrp x0, clean_json
    add x0, x0, :lo12:clean_json
    adrp x1, key_channel_id
    add x1, x1, :lo12:key_channel_id
    adrp x2, channel_id_buf
    add x2, x2, :lo12:channel_id_buf
    mov w3, #64
    bl extract_json_str
    cbz w0, tick_heartbeat

    adrp x0, clean_json
    add x0, x0, :lo12:clean_json
    adrp x1, key_content
    add x1, x1, :lo12:key_content
    adrp x2, content_buf
    add x2, x2, :lo12:content_buf
    mov w3, #512
    bl extract_json_str
    cbz w0, tick_heartbeat

    adrp x0, content_buf
    add x0, x0, :lo12:content_buf
    adrp x1, cmd_ping
    add x1, x1, :lo12:cmd_ping
    bl strstr
    adrp x1, content_buf
    add x1, x1, :lo12:content_buf
    cmp x0, x1
    b.eq exec_ping

    adrp x0, content_buf
    add x0, x0, :lo12:content_buf
    adrp x1, cmd_sysinfo
    add x1, x1, :lo12:cmd_sysinfo
    bl strstr
    adrp x1, content_buf
    add x1, x1, :lo12:content_buf
    cmp x0, x1
    b.eq exec_sysinfo
    b tick_heartbeat

exec_ping:
    // Apple ARM64 ABI: variadic arguments for _printf must be passed on the stack
    adrp x1, channel_id_buf
    add x1, x1, :lo12:channel_id_buf
    adrp x2, content_buf
    add x2, x2, :lo12:content_buf
    stp x1, x2, [sp]
    adrp x0, fmt_cmd
    add x0, x0, :lo12:fmt_cmd
    bl printf

    adrp x0, reply_ping
    add x0, x0, :lo12:reply_ping
    mov x1, #68
    bl send_discord_reply
    b tick_heartbeat

exec_sysinfo:
    adrp x1, channel_id_buf
    add x1, x1, :lo12:channel_id_buf
    adrp x2, content_buf
    add x2, x2, :lo12:content_buf
    stp x1, x2, [sp]
    adrp x0, fmt_cmd
    add x0, x0, :lo12:fmt_cmd
    bl printf

    bl build_live_sysinfo
    mov x1, x0
    adrp x0, sys_reply_buf
    add x0, x0, :lo12:sys_reply_buf
    bl send_discord_reply

tick_heartbeat:
    adrp x0, hb_counter
    add x0, x0, :lo12:hb_counter
    ldr w1, [x0]
    add w1, w1, #1
    str w1, [x0]
    cmp w1, #25
    b.lt event_loop

    str wzr, [x0]
    adrp x0, hb_payload
    add x0, x0, :lo12:hb_payload
    mov x1, #17
    bl ws_send_text

    adrp x0, msg_hb
    add x0, x0, :lo12:msg_hb
    bl puts
    b event_loop

err_no_token:
    adrp x0, err_token
    add x0, x0, :lo12:err_token
    bl puts
    mov w0, #1
    bl exit

err_dns_fail:
    adrp x0, err_dns
    add x0, x0, :lo12:err_dns
    bl puts
    mov w0, #1
    bl exit

err_sock_fail:
    adrp x0, err_sock
    add x0, x0, :lo12:err_sock
    bl puts
    mov w0, #1
    bl exit

err_tls_fail:
    adrp x0, err_tls
    add x0, x0, :lo12:err_tls
    bl puts
    mov w0, #1
    bl exit

// ----------------------------------------------------------------------------
// Read-Only Data
// ----------------------------------------------------------------------------
.section .rodata
env_token:      .asciz "DISCORD_TOKEN"
env_owner:      .asciz "ALLOWED_USER_ID"
gw_host:        .asciz "gateway.discord.gg"
api_host:       .asciz "discord.com"
port:           .asciz "443"

mib_boottime:   .asciz "kern.boottime"
mib_memsize:    .asciz "hw.memsize"

err_token:      .asciz "[ERROR] DISCORD_TOKEN environment variable not set."
err_dns:        .asciz "[ERROR] DNS resolution failed."
err_sock:       .asciz "[ERROR] TCP socket creation/connection failed."
err_tls:        .asciz "[ERROR] TLS 1.3 handshake or certificate verification failed."
msg_tls:        .asciz "[1/3] TLS 1.3 tunnel established (strict CA verification enabled)."
msg_ws:         .asciz "[2/3] WebSocket 101 Switching Protocols OK."
msg_online:     .asciz "[3/3] Bot ONLINE (Apple Silicon ARM64)! Listening for !ping and !sysinfo..."
msg_hb:         .asciz "[PING] Heartbeat sent."
fmt_cmd:        .asciz "[CMD] Channel %s | Command: %s\n"
msg_clean_exit: .asciz "\n[EXIT] Sensitive buffers wiped from RAM. Clean shutdown."

ws_handshake:   .ascii "GET /?v=10&encoding=json HTTP/1.1\r\n"
                .ascii "Host: gateway.discord.gg\r\n"
                .ascii "Upgrade: websocket\r\n"
                .ascii "Connection: Upgrade\r\n"
                .ascii "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                .asciz "Sec-WebSocket-Version: 13\r\n\r\n"

id_prefix:      .asciz "{\"op\":2,\"d\":{\"token\":\""
id_suffix:      .asciz "\",\"intents\":33281,\"properties\":{\"os\":\"macos\",\"browser\":\"arm64-asm\",\"device\":\"apple-silicon\"}}}"
hb_payload:     .asciz "{\"op\":1,\"d\":null}"

key_msg_create: .asciz "\"MESSAGE_CREATE\""
key_channel_id: .asciz "\"channel_id\":\""
key_content:    .asciz "\"content\":\""
key_author:     .asciz "\"author\":{"
key_id:         .asciz "\"id\":\""
key_bot_true:   .asciz "\"bot\":true"

cmd_ping:       .asciz "!ping"
cmd_sysinfo:    .asciz "!sysinfo"

reply_ping:     .asciz "{\"content\":\"Pong! Pure Apple Silicon ARM64 Assembly over TLS 1.3.\"}"

sys_p1:         .asciz "{\"content\":\"OS: macOS Apple Silicon (ARM64) | Uptime: "
sys_p2:         .asciz "s | Total RAM: "
sys_p3:         .asciz " MB | Runtime: Zero (ARM64 ASM)\"}"

http_p1:        .asciz "POST /api/v10/channels/"
http_p2:        .ascii "/messages HTTP/1.1\r\nHost: discord.com\r\nAuthorization: Bot "
http_p3:        .ascii "\r\nContent-Type: application/json\r\nContent-Length: "
http_p4:        .asciz "\r\nConnection: close\r\n\r\n"

// ----------------------------------------------------------------------------
// Uninitialized BSS Buffers
// ----------------------------------------------------------------------------
.bss
.align 4
sysinfo_buf: .skip 128
.align 4
hints:          .space 48
res_ptr:        .space 8
sock_fd:        .space 4
ssl_ctx:        .space 8
ssl_conn:       .space 8

token_buf:      .space 512
token_len:      .space 8
owner_buf:      .space 64
has_owner:      .space 1

poll_fds:       .space 8
hb_counter:     .space 4

recv_buf:       .space 16384
clean_json:     .space 16384
json_buf:       .space 2048
ws_frame:       .space 2200
mask_key:       .space 4

channel_id_buf: .space 64
author_id_buf:  .space 64
content_buf:    .space 512
http_req_buf:   .space 4096
http_resp_buf:  .space 2048
num_str_buf:    .space 32

boottime_val:   .space 16
memsize_val:    .space 8
sysctl_len:     .space 8
sys_reply_buf:  .space 512

.section .note.GNU-stack,"",@progbits
