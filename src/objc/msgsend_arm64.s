// objc_msgSend family for arm64 (Mach-O). Same global cache layout as x86_64.
    .text
.macro LOOKUP
    adrp x9, __scion_objc_cache@PAGE
    ldr x9, [x9, __scion_objc_cache@PAGEOFF]
    ldr x10, [x9]
    lsr x11, x16, #4
    eor x11, x11, x1, lsr #3
    and x11, x11, x10
1:  add x12, x9, x11, lsl #5
    add x14, x12, #32
    ldar x13, [x14]
    cbz x13, 3f
    cmp x13, x16
    b.ne 2f
    ldr x13, [x12, #40]
    cmp x13, x1
    b.ne 2f
    ldr x17, [x12, #48]
    br x17
2:  add x11, x11, #1
    and x11, x11, x10
    b 1b
3:  stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #208
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    str x8, [sp, #64]
    stp q0, q1, [sp, #80]
    stp q2, q3, [sp, #112]
    stp q4, q5, [sp, #144]
    stp q6, q7, [sp, #176]
    mov x2, x16
    bl __scion_objc_lookup
    mov x17, x0
    ldp x0, x1, [sp, #0]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldr x8, [sp, #64]
    ldp q0, q1, [sp, #80]
    ldp q2, q3, [sp, #112]
    ldp q4, q5, [sp, #144]
    ldp q6, q7, [sp, #176]
    mov sp, x29
    ldp x29, x30, [sp], #16
    br x17
.endm

    .globl _objc_msgSend
    .p2align 2
_objc_msgSend:
    cbz x0, Lnil
    ldr x16, [x0]
    LOOKUP
Lnil:
    mov x1, #0
    movi d0, #0
    movi d1, #0
    movi d2, #0
    movi d3, #0
    ret

    .globl _objc_msgSendSuper
    .p2align 2
_objc_msgSendSuper:
    ldr x16, [x0, #8]
    ldr x0, [x0]
    LOOKUP

    .globl _objc_msgSendSuper2
    .p2align 2
_objc_msgSendSuper2:
    ldr x16, [x0, #8]
    ldr x16, [x16, #8]
    ldr x0, [x0]
    LOOKUP

    .globl __objc_msgForward
    .p2align 2
__objc_msgForward:
    .cfi_startproc
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    sub sp, sp, #208
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    str x8, [sp, #64]
    stp q0, q1, [sp, #80]
    stp q2, q3, [sp, #112]
    stp q4, q5, [sp, #144]
    stp q6, q7, [sp, #176]
    mov x2, sp
    bl __scion_objc_forward_target
    cbz x0, Lfwd_done
    ldr x1, [sp, #8]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldr x8, [sp, #64]
    ldp q0, q1, [sp, #80]
    ldp q2, q3, [sp, #112]
    ldp q4, q5, [sp, #144]
    ldp q6, q7, [sp, #176]
    mov sp, x29
    ldp x29, x30, [sp], #16
    b _objc_msgSend
Lfwd_done:                      // the invocation ran: its return value is in the frame (x0/x1 at 0, q0-q3 at 80)
    ldp x0, x1, [sp, #0]
    ldp q0, q1, [sp, #80]
    ldp q2, q3, [sp, #112]
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret
    .cfi_endproc

// __scion_objc_invoke(frame, imp, stack args, stack bytes): calls imp with the registers of a frame laid out as above
// (x0-x7 at 0, x8 at 64, q0-q7 at 80), then stores x0, x1 and q0-q3 back in it (NSInvocation -invoke)
    .globl __scion_objc_invoke
    .p2align 2
__scion_objc_invoke:
    .cfi_startproc
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    .cfi_def_cfa w29, 32
    .cfi_offset w30, -24
    .cfi_offset w29, -32
    str x19, [sp, #16]
    .cfi_offset w19, -16
    mov x19, x0
    mov x9, x1
    sub sp, sp, x3
    mov x10, #0
1:  cmp x10, x3
    b.ge 2f
    ldr x11, [x2, x10]
    str x11, [sp, x10]
    add x10, x10, #8
    b 1b
2:  ldp x0, x1, [x19, #0]
    ldp x2, x3, [x19, #16]
    ldp x4, x5, [x19, #32]
    ldp x6, x7, [x19, #48]
    ldr x8, [x19, #64]
    ldp q0, q1, [x19, #80]
    ldp q2, q3, [x19, #112]
    ldp q4, q5, [x19, #144]
    ldp q6, q7, [x19, #176]
    blr x9
    stp x0, x1, [x19, #0]
    stp q0, q1, [x19, #80]
    stp q2, q3, [x19, #112]
    mov sp, x29
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
    .cfi_endproc
