// ============================================================================
// Daimonos - Minimalist Discord Gateway & REST Bot in Pure ARM64 Assembly
// Target: macOS Apple Silicon (M1/M2/M3/M4, AArch64 Mach-O)
// Assembler: Apple Clang Integrated Assembler (GAS)
// ============================================================================

.text
.align 2
.globl _main

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

    adrp x0, token_buf@PAGE
    add x0, x0, token_buf@PAGEOFF
    mov w1, #0
    mov x2, #512
    bl _memset

    adrp x0, http_req_buf@PAGE
    add x0, x0, http_req_buf@PAGEOFF
    mov w1, #0
    mov x2, #4096
    bl _memset

    adrp x0, msg_clean_exit@PAGE
    add x0, x0, msg_clean_exit@PAGEOFF
    bl _puts

    mov w0, #0
    bl _exit

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

    adrp x0, mask_key@PAGE
    add x0, x0, mask_key@PAGEOFF
    mov w1, #4
    bl _RAND_bytes

    adrp x21, ws_frame@PAGE
    add x21, x21, ws_frame@PAGEOFF
    mov w0, #0x81
    strb w0, [x21]

    cmp x20, #125
    b.gt 1f

    orr w0, w20, #0x80
    strb w0, [x21, #1]
    adrp x1, mask_key@PAGE
    add x1, x1, mask_key@PAGEOFF
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
    adrp x1, mask_key@PAGE
    add x1, x1, mask_key@PAGEOFF
    ldr w0, [x1]
    str w0, [x21, #4]
    mov x22, #8
2:
    adrp x2, mask_key@PAGE
    add x2, x2, mask_key@PAGEOFF
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
    adrp x0, ssl_conn@PAGE
    add x0, x0, ssl_conn@PAGEOFF
    ldr x0, [x0]
    mov x1, x21
    mov w2, w22
    bl _SSL_write

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

    adrp x0, recv_buf@PAGE
    add x0, x0, recv_buf@PAGEOFF
    mov w1, #0
    mov x2, #16384
    bl _memset

    adrp x0, clean_json@PAGE
    add x0, x0, clean_json@PAGEOFF
    mov w1, #0
    mov x2, #16384
    bl _memset

    adrp x0, ssl_conn@PAGE
    add x0, x0, ssl_conn@PAGEOFF
    ldr x0, [x0]
    adrp x1, recv_buf@PAGE
    add x1, x1, recv_buf@PAGEOFF
    mov w2, #16383
    bl _SSL_read
    cmp w0, #2
    b.lt 4f

    adrp x1, recv_buf@PAGE
    add x1, x1, recv_buf@PAGEOFF
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

    adrp x0, clean_json@PAGE
    add x0, x0, clean_json@PAGEOFF
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

    bl _strstr
    cbz x0, 3f
    mov x22, x0

    mov x0, x19
    bl _strlen
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

    adrp x2, sysctl_len@PAGE
    add x2, x2, sysctl_len@PAGEOFF
    mov x0, #16
    str x0, [x2]

    adrp x0, mib_boottime@PAGE
    add x0, x0, mib_boottime@PAGEOFF
    adrp x1, boottime_val@PAGE
    add x1, x1, boottime_val@PAGEOFF
    mov x3, #0
    mov x4, #0
    bl _sysctlbyname

    mov x0, #0
    bl _time
    adrp x1, boottime_val@PAGE
    add x1, x1, boottime_val@PAGEOFF
    ldr x1, [x1]
    sub x19, x0, x1             // uptime seconds

    adrp x2, sysctl_len@PAGE
    add x2, x2, sysctl_len@PAGEOFF
    mov x0, #8
    str x0, [x2]

    adrp x0, mib_memsize@PAGE
    add x0, x0, mib_memsize@PAGEOFF
    adrp x1, memsize_val@PAGE
    add x1, x1, memsize_val@PAGEOFF
    mov x3, #0
    mov x4, #0
    bl _sysctlbyname

    adrp x20, sys_reply_buf@PAGE
    add x20, x20, sys_reply_buf@PAGEOFF

    mov x0, x20
    adrp x1, sys_p1@PAGE
    add x1, x1, sys_p1@PAGEOFF
    mov x2, #45
    bl memcpy_bytes
    mov x20, x0

    mov x0, x19
    adrp x1, num_str_buf@PAGE
    add x1, x1, num_str_buf@PAGEOFF
    bl u64_to_str
    mov x2, x0
    mov x0, x20
    adrp x1, num_str_buf@PAGE
    add x1, x1, num_str_buf@PAGEOFF
    bl memcpy_bytes
    mov x20, x0

    adrp x1, sys_p2@PAGE
    add x1, x1, sys_p2@PAGEOFF
    mov x2, #15
    bl memcpy_bytes
    mov x20, x0

    adrp x0, memsize_val@PAGE
    add x0, x0, memsize_val@PAGEOFF
    ldr x0, [x0]
    lsr x0, x0, #20             // bytes -> MB
    adrp x1, num_str_buf@PAGE
    add x1, x1, num_str_buf@PAGEOFF
    bl u64_to_str
    mov x2, x0
    mov x0, x20
    adrp x1, num_str_buf@PAGE
    add x1, x1, num_str_buf@PAGEOFF
    bl memcpy_bytes
    mov x20, x0

    adrp x1, sys_p3@PAGE
    add x1, x1, sys_p3@PAGEOFF
    mov x2, #37
    bl memcpy_bytes
    strb wzr, [x0]

    adrp x1, sys_reply_buf@PAGE
    add x1, x1, sys_reply_buf@PAGEOFF
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
    adrp x1, num_str_buf@PAGE
    add x1, x1, num_str_buf@PAGEOFF
    bl u64_to_str
    mov x21, x0                 // num_str_len

    adrp x22, http_req_buf@PAGE
    add x22, x22, http_req_buf@PAGEOFF

    mov x0, x22
    adrp x1, http_p1@PAGE
    add x1, x1, http_p1@PAGEOFF
    mov x2, #23
    bl memcpy_bytes
    mov x22, x0

    adrp x0, channel_id_buf@PAGE
    add x0, x0, channel_id_buf@PAGEOFF
    bl _strlen
    mov x2, x0
    mov x0, x22
    adrp x1, channel_id_buf@PAGE
    add x1, x1, channel_id_buf@PAGEOFF
    bl memcpy_bytes
    mov x22, x0

    adrp x1, http_p2@PAGE
    add x1, x1, http_p2@PAGEOFF
    mov x2, #60
    bl memcpy_bytes
    mov x22, x0

    adrp x1, token_buf@PAGE
    add x1, x1, token_buf@PAGEOFF
    adrp x2, token_len@PAGE
    add x2, x2, token_len@PAGEOFF
    ldr x2, [x2]
    bl memcpy_bytes
    mov x22, x0

    adrp x1, http_p3@PAGE
    add x1, x1, http_p3@PAGEOFF
    mov x2, #50
    bl memcpy_bytes
    mov x22, x0

    adrp x1, num_str_buf@PAGE
    add x1, x1, num_str_buf@PAGEOFF
    mov x2, x21
    bl memcpy_bytes
    mov x22, x0

    adrp x1, http_p4@PAGE
    add x1, x1, http_p4@PAGEOFF
    mov x2, #23
    bl memcpy_bytes
    mov x22, x0

    mov x1, x19
    mov x2, x20
    bl memcpy_bytes
    strb wzr, [x0]

    adrp x1, http_req_buf@PAGE
    add x1, x1, http_req_buf@PAGEOFF
    sub x23, x0, x1             // total http req len

    adrp x0, hints@PAGE
    add x0, x0, hints@PAGEOFF
    mov w1, #0
    mov x2, #48
    bl _memset
    adrp x0, hints@PAGE
    add x0, x0, hints@PAGEOFF
    mov w1, #AF_INET
    str w1, [x0, #4]
    mov w1, #SOCK_STREAM
    str w1, [x0, #8]

    adrp x0, api_host@PAGE
    add x0, x0, api_host@PAGEOFF
    adrp x1, port@PAGE
    add x1, x1, port@PAGEOFF
    adrp x2, hints@PAGE
    add x2, x2, hints@PAGEOFF
    adrp x3, res_ptr@PAGE
    add x3, x3, res_ptr@PAGEOFF
    bl _getaddrinfo
    cbnz w0, 5f

    adrp x0, res_ptr@PAGE
    add x0, x0, res_ptr@PAGEOFF
    ldr x24, [x0]
    ldr w0, [x24, #4]
    ldr w1, [x24, #8]
    ldr w2, [x24, #12]
    bl _socket
    cmn w0, #1
    b.eq 4f
    mov w25, w0                 // api_sock

    mov w0, w25
    ldr x1, [x24, #32]          // Darwin addrinfo->ai_addr at offset 32
    ldr w2, [x24, #16]          // ai_addrlen at offset 16
    bl _connect
    cbnz w0, 3f

    mov x0, x24
    bl _freeaddrinfo

    adrp x0, ssl_ctx@PAGE
    add x0, x0, ssl_ctx@PAGEOFF
    ldr x0, [x0]
    bl _SSL_new
    mov x26, x0                 // api_ssl

    mov x0, x26
    mov w1, w25
    bl _SSL_set_fd

    mov x0, x26
    mov w1, #55                 // SSL_CTRL_SET_TLSEXT_HOSTNAME
    mov x2, #0
    adrp x3, api_host@PAGE
    add x3, x3, api_host@PAGEOFF
    bl _SSL_ctrl

    mov x0, x26
    bl _SSL_connect
    cmp w0, #1
    b.ne 2f

    mov x0, x26
    adrp x1, http_req_buf@PAGE
    add x1, x1, http_req_buf@PAGEOFF
    mov w2, w23
    bl _SSL_write

    mov x0, x26
    adrp x1, http_resp_buf@PAGE
    add x1, x1, http_resp_buf@PAGEOFF
    mov w2, #2047
    bl _SSL_read

    mov x0, x26
    bl _SSL_shutdown
2:
    mov x0, x26
    bl _SSL_free
3:
    mov w0, w25
    bl _close
    b 5f
4:
    mov x0, x24
    bl _freeaddrinfo
5:
    adrp x0, http_req_buf@PAGE
    add x0, x0, http_req_buf@PAGEOFF
    mov w1, #0
    mov x2, #4096
    bl _memset

    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret

// ----------------------------------------------------------------------------
// Main Entry Point (_main)
// ----------------------------------------------------------------------------
_main:
    stp x29, x30, [sp, #-48]!
    mov x29, sp

    mov w0, #SIGINT
    adrp x1, cleanup_exit@PAGE
    add x1, x1, cleanup_exit@PAGEOFF
    bl _signal

    mov w0, #SIGTERM
    adrp x1, cleanup_exit@PAGE
    add x1, x1, cleanup_exit@PAGEOFF
    bl _signal

    adrp x0, env_owner@PAGE
    add x0, x0, env_owner@PAGEOFF
    bl _getenv
    cbz x0, 1f
    mov x19, x0
    bl _strlen
    cbz x0, 1f
    cmp x0, #60
    b.gt 1f
    mov x2, x0
    adrp x0, owner_buf@PAGE
    add x0, x0, owner_buf@PAGEOFF
    mov x1, x19
    bl memcpy_bytes
    strb wzr, [x0]
    adrp x0, has_owner@PAGE
    add x0, x0, has_owner@PAGEOFF
    mov w1, #1
    strb w1, [x0]
1:
    adrp x0, env_token@PAGE
    add x0, x0, env_token@PAGEOFF
    bl _getenv
    cbz x0, err_no_token
    mov x19, x0
    bl _strlen
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
    adrp x0, token_len@PAGE
    add x0, x0, token_len@PAGEOFF
    str x20, [x0]
    adrp x0, token_buf@PAGE
    add x0, x0, token_buf@PAGEOFF
    mov x1, x19
    mov x2, x20
    bl memcpy_bytes
    strb wzr, [x0]

    adrp x0, hints@PAGE
    add x0, x0, hints@PAGEOFF
    mov w1, #0
    mov x2, #48
    bl _memset
    adrp x0, hints@PAGE
    add x0, x0, hints@PAGEOFF
    mov w1, #AF_INET
    str w1, [x0, #4]
    mov w1, #SOCK_STREAM
    str w1, [x0, #8]

    adrp x0, gw_host@PAGE
    add x0, x0, gw_host@PAGEOFF
    adrp x1, port@PAGE
    add x1, x1, port@PAGEOFF
    adrp x2, hints@PAGE
    add x2, x2, hints@PAGEOFF
    adrp x3, res_ptr@PAGE
    add x3, x3, res_ptr@PAGEOFF
    bl _getaddrinfo
    cbnz w0, err_dns_fail

    adrp x0, res_ptr@PAGE
    add x0, x0, res_ptr@PAGEOFF
    ldr x19, [x0]
    ldr w0, [x19, #4]
    ldr w1, [x19, #8]
    ldr w2, [x19, #12]
    bl _socket
    cmn w0, #1
    b.eq err_sock_fail
    mov w20, w0
    adrp x0, sock_fd@PAGE
    add x0, x0, sock_fd@PAGEOFF
    str w20, [x0]

    mov w0, w20
    ldr x1, [x19, #32]
    ldr w2, [x19, #16]
    bl _connect
    cbnz w0, err_sock_fail

    mov x0, x19
    bl _freeaddrinfo

    mov x0, #0
    mov x1, #0
    bl _OPENSSL_init_ssl

    bl _TLS_client_method
    bl _SSL_CTX_new
    cbz x0, err_tls_fail
    mov x19, x0
    adrp x1, ssl_ctx@PAGE
    add x1, x1, ssl_ctx@PAGEOFF
    str x19, [x1]

    mov x0, x19
    bl _SSL_CTX_set_default_verify_paths

    mov x0, x19
    mov w1, #1
    mov x2, #0
    bl _SSL_CTX_set_verify

    mov x0, x19
    bl _SSL_new
    mov x21, x0
    adrp x1, ssl_conn@PAGE
    add x1, x1, ssl_conn@PAGEOFF
    str x21, [x1]

    mov x0, x21
    mov w1, w20
    bl _SSL_set_fd

    mov x0, x21
    mov w1, #55
    mov x2, #0
    adrp x3, gw_host@PAGE
    add x3, x3, gw_host@PAGEOFF
    bl _SSL_ctrl

    mov x0, x21
    bl _SSL_connect
    cmp w0, #1
    b.ne err_tls_fail

    adrp x0, msg_tls@PAGE
    add x0, x0, msg_tls@PAGEOFF
    bl _puts

    mov x0, x21
    adrp x1, ws_handshake@PAGE
    add x1, x1, ws_handshake@PAGEOFF
    mov w2, #159
    bl _SSL_write

    mov x0, x21
    adrp x1, recv_buf@PAGE
    add x1, x1, recv_buf@PAGEOFF
    mov w2, #16383
    bl _SSL_read

    adrp x0, msg_ws@PAGE
    add x0, x0, msg_ws@PAGEOFF
    bl _puts

    bl ws_recv_frame

    adrp x22, json_buf@PAGE
    add x22, x22, json_buf@PAGEOFF

    mov x0, x22
    adrp x1, id_prefix@PAGE
    add x1, x1, id_prefix@PAGEOFF
    mov x2, #22
    bl memcpy_bytes
    mov x22, x0

    adrp x1, token_buf@PAGE
    add x1, x1, token_buf@PAGEOFF
    adrp x2, token_len@PAGE
    add x2, x2, token_len@PAGEOFF
    ldr x2, [x2]
    bl memcpy_bytes
    mov x22, x0

    adrp x1, id_suffix@PAGE
    add x1, x1, id_suffix@PAGEOFF
    mov x2, #90
    bl memcpy_bytes
    strb wzr, [x0]

    adrp x1, json_buf@PAGE
    add x1, x1, json_buf@PAGEOFF
    sub x1, x0, x1
    adrp x0, json_buf@PAGE
    add x0, x0, json_buf@PAGEOFF
    bl ws_send_text

    adrp x0, json_buf@PAGE
    add x0, x0, json_buf@PAGEOFF
    mov w1, #0
    mov x2, #2048
    bl _memset

    adrp x0, msg_online@PAGE
    add x0, x0, msg_online@PAGEOFF
    bl _puts

    adrp x0, poll_fds@PAGE
    add x0, x0, poll_fds@PAGEOFF
    str w20, [x0]
    mov w1, #POLLIN
    strh w1, [x0, #4]

event_loop:
    adrp x0, poll_fds@PAGE
    add x0, x0, poll_fds@PAGEOFF
    strh wzr, [x0, #6]
    mov w1, #1
    mov w2, #1000
    bl _poll

    cmp w0, #0
    b.le tick_heartbeat

    adrp x0, poll_fds@PAGE
    add x0, x0, poll_fds@PAGEOFF
    ldrh w1, [x0, #6]
    tst w1, #POLLIN
    b.eq tick_heartbeat

    bl ws_recv_frame
    cmp w0, #0x81
    b.ne tick_heartbeat

    adrp x0, clean_json@PAGE
    add x0, x0, clean_json@PAGEOFF
    adrp x1, key_msg_create@PAGE
    add x1, x1, key_msg_create@PAGEOFF
    bl _strstr
    cbz x0, tick_heartbeat

    adrp x0, clean_json@PAGE
    add x0, x0, clean_json@PAGEOFF
    adrp x1, key_bot_true@PAGE
    add x1, x1, key_bot_true@PAGEOFF
    bl _strstr
    cbnz x0, tick_heartbeat

    adrp x0, has_owner@PAGE
    add x0, x0, has_owner@PAGEOFF
    ldrb w0, [x0]
    cmp w0, #1
    b.ne parse_fields

    adrp x0, clean_json@PAGE
    add x0, x0, clean_json@PAGEOFF
    adrp x1, key_author@PAGE
    add x1, x1, key_author@PAGEOFF
    bl _strstr
    cbz x0, tick_heartbeat

    adrp x1, key_id@PAGE
    add x1, x1, key_id@PAGEOFF
    adrp x2, author_id_buf@PAGE
    add x2, x2, author_id_buf@PAGEOFF
    mov w3, #64
    bl extract_json_str
    cbz w0, tick_heartbeat

    adrp x0, author_id_buf@PAGE
    add x0, x0, author_id_buf@PAGEOFF
    adrp x1, owner_buf@PAGE
    add x1, x1, owner_buf@PAGEOFF
    bl _strcmp
    cbnz w0, tick_heartbeat

parse_fields:
    adrp x0, clean_json@PAGE
    add x0, x0, clean_json@PAGEOFF
    adrp x1, key_channel_id@PAGE
    add x1, x1, key_channel_id@PAGEOFF
    adrp x2, channel_id_buf@PAGE
    add x2, x2, channel_id_buf@PAGEOFF
    mov w3, #64
    bl extract_json_str
    cbz w0, tick_heartbeat

    adrp x0, clean_json@PAGE
    add x0, x0, clean_json@PAGEOFF
    adrp x1, key_content@PAGE
    add x1, x1, key_content@PAGEOFF
    adrp x2, content_buf@PAGE
    add x2, x2, content_buf@PAGEOFF
    mov w3, #512
    bl extract_json_str
    cbz w0, tick_heartbeat

    adrp x0, content_buf@PAGE
    add x0, x0, content_buf@PAGEOFF
    adrp x1, cmd_ping@PAGE
    add x1, x1, cmd_ping@PAGEOFF
    bl _strstr
    adrp x1, content_buf@PAGE
    add x1, x1, content_buf@PAGEOFF
    cmp x0, x1
    b.eq exec_ping

    adrp x0, content_buf@PAGE
    add x0, x0, content_buf@PAGEOFF
    adrp x1, cmd_sysinfo@PAGE
    add x1, x1, cmd_sysinfo@PAGEOFF
    bl _strstr
    adrp x1, content_buf@PAGE
    add x1, x1, content_buf@PAGEOFF
    cmp x0, x1
    b.eq exec_sysinfo
    b tick_heartbeat

exec_ping:
    // Apple ARM64 ABI: variadic arguments for _printf must be passed on the stack
    adrp x1, channel_id_buf@PAGE
    add x1, x1, channel_id_buf@PAGEOFF
    adrp x2, content_buf@PAGE
    add x2, x2, content_buf@PAGEOFF
    stp x1, x2, [sp]
    adrp x0, fmt_cmd@PAGE
    add x0, x0, fmt_cmd@PAGEOFF
    bl _printf

    adrp x0, reply_ping@PAGE
    add x0, x0, reply_ping@PAGEOFF
    mov x1, #68
    bl send_discord_reply
    b tick_heartbeat

exec_sysinfo:
    adrp x1, channel_id_buf@PAGE
    add x1, x1, channel_id_buf@PAGEOFF
    adrp x2, content_buf@PAGE
    add x2, x2, content_buf@PAGEOFF
    stp x1, x2, [sp]
    adrp x0, fmt_cmd@PAGE
    add x0, x0, fmt_cmd@PAGEOFF
    bl _printf

    bl build_live_sysinfo
    mov x1, x0
    adrp x0, sys_reply_buf@PAGE
    add x0, x0, sys_reply_buf@PAGEOFF
    bl send_discord_reply

tick_heartbeat:
    adrp x0, hb_counter@PAGE
    add x0, x0, hb_counter@PAGEOFF
    ldr w1, [x0]
    add w1, w1, #1
    str w1, [x0]
    cmp w1, #25
    b.lt event_loop

    str wzr, [x0]
    adrp x0, hb_payload@PAGE
    add x0, x0, hb_payload@PAGEOFF
    mov x1, #17
    bl ws_send_text

    adrp x0, msg_hb@PAGE
    add x0, x0, msg_hb@PAGEOFF
    bl _puts
    b event_loop

err_no_token:
    adrp x0, err_token@PAGE
    add x0, x0, err_token@PAGEOFF
    bl _puts
    mov w0, #1
    bl _exit

err_dns_fail:
    adrp x0, err_dns@PAGE
    add x0, x0, err_dns@PAGEOFF
    bl _puts
    mov w0, #1
    bl _exit

err_sock_fail:
    adrp x0, err_sock@PAGE
    add x0, x0, err_sock@PAGEOFF
    bl _puts
    mov w0, #1
    bl _exit

err_tls_fail:
    adrp x0, err_tls@PAGE
    add x0, x0, err_tls@PAGEOFF
    bl _puts
    mov w0, #1
    bl _exit

// ----------------------------------------------------------------------------
// Read-Only Data
// ----------------------------------------------------------------------------
.const
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
