# objc_msgSend family for x86_64 (Mach-O). Global cache probe: idx = ((cls>>4) ^ (sel>>3)) & mask,
# entries of 32 bytes at table+32: {isa, sel, imp, pad}. Only r10/r11 are free, rax (AL = vector count
# for variadic calls) is saved around the probe.
    .text
.macro LOOKUP selfreg, selreg
    pushq %rax
    movq \selreg, %rax
    shrq $3, %rax
    movq %r10, %r11
    shrq $4, %r11
    xorq %r11, %rax
    shlq $5, %rax
    movq __scion_objc_cache(%rip), %r11
    andq 8(%r11), %rax
1:  cmpq $0, 32(%r11,%rax)
    je 3f
    cmpq %r10, 32(%r11,%rax)
    jne 2f
    cmpq \selreg, 40(%r11,%rax)
    jne 2f
    movq 48(%r11,%rax), %r11
    popq %rax
    jmpq *%r11
2:  addq $32, %rax
    andq 8(%r11), %rax
    jmp 1b
3:  subq $192, %rsp
    movq %rdi, 0(%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movq %rcx, 24(%rsp)
    movq %r8, 32(%rsp)
    movq %r9, 40(%rsp)
    movdqa %xmm0, 48(%rsp)
    movdqa %xmm1, 64(%rsp)
    movdqa %xmm2, 80(%rsp)
    movdqa %xmm3, 96(%rsp)
    movdqa %xmm4, 112(%rsp)
    movdqa %xmm5, 128(%rsp)
    movdqa %xmm6, 144(%rsp)
    movdqa %xmm7, 160(%rsp)
    movq \selfreg, %rdi
    movq \selreg, %rsi
    movq %r10, %rdx
    call __scion_objc_lookup
    movq %rax, %r11
    movq 0(%rsp), %rdi
    movq 8(%rsp), %rsi
    movq 16(%rsp), %rdx
    movq 24(%rsp), %rcx
    movq 32(%rsp), %r8
    movq 40(%rsp), %r9
    movdqa 48(%rsp), %xmm0
    movdqa 64(%rsp), %xmm1
    movdqa 80(%rsp), %xmm2
    movdqa 96(%rsp), %xmm3
    movdqa 112(%rsp), %xmm4
    movdqa 128(%rsp), %xmm5
    movdqa 144(%rsp), %xmm6
    movdqa 160(%rsp), %xmm7
    addq $192, %rsp
    popq %rax
    jmpq *%r11
.endm

    .globl _objc_msgSend
    .p2align 4
_objc_msgSend:
    testq %rdi, %rdi
    jz Lnil
    movq (%rdi), %r10
    LOOKUP %rdi, %rsi
Lnil:
    xorl %eax, %eax
    xorl %edx, %edx
    xorps %xmm0, %xmm0
    xorps %xmm1, %xmm1
    ret

    .globl _objc_msgSendSuper
    .p2align 4
_objc_msgSendSuper:            # rdi = struct objc_super {receiver, class}
    movq 8(%rdi), %r10
    movq (%rdi), %rdi
    LOOKUP %rdi, %rsi

    .globl _objc_msgSendSuper2
    .p2align 4
_objc_msgSendSuper2:           # {receiver, current class}: start at current->superclass
    movq 8(%rdi), %r10
    movq 8(%r10), %r10
    movq (%rdi), %rdi
    LOOKUP %rdi, %rsi

    .globl _objc_msgSend_stret
    .p2align 4
_objc_msgSend_stret:           # rdi = result, rsi = self, rdx = sel
    testq %rsi, %rsi
    jz Lnil_stret
    movq (%rsi), %r10
    LOOKUP %rsi, %rdx
Lnil_stret:
    movq %rdi, %rax
    ret

    .globl _objc_msgSendSuper2_stret
    .p2align 4
_objc_msgSendSuper2_stret:
    movq 8(%rsi), %r10
    movq 8(%r10), %r10
    movq (%rsi), %rsi
    LOOKUP %rsi, %rdx

    .globl _objc_msgSendSuper_stret
    .p2align 4
_objc_msgSendSuper_stret:
    movq 8(%rsi), %r10
    movq (%rsi), %rsi
    LOOKUP %rsi, %rdx

    .globl _objc_msgSend_fpret
    .p2align 4
_objc_msgSend_fpret:           # long double return in st(0)
    testq %rdi, %rdi
    jz Lnil_fp
    movq (%rdi), %r10
    LOOKUP %rdi, %rsi
Lnil_fp:
    fldz
    ret

    .globl _objc_msgSend_fp2ret
    .p2align 4
_objc_msgSend_fp2ret:
    testq %rdi, %rdi
    jz Lnil_fp2
    movq (%rdi), %r10
    LOOKUP %rdi, %rsi
Lnil_fp2:
    fldz
    fldz
    ret

# forwarding: a forwarding target (resend to it), or an NSInvocation made from the saved registers (the frame below,
# described in objc.c: gprs at 0, xmm0-7 at 48, stack arguments at 208); a NULL target means the invocation ran and its
# return value is in the frame
    .globl __objc_msgForward
    .p2align 4
__objc_msgForward:
    .cfi_startproc
    pushq %rax
    .cfi_adjust_cfa_offset 8
    subq $192, %rsp
    .cfi_adjust_cfa_offset 192
    movq %rdi, 0(%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movq %rcx, 24(%rsp)
    movq %r8, 32(%rsp)
    movq %r9, 40(%rsp)
    movdqa %xmm0, 48(%rsp)
    movdqa %xmm1, 64(%rsp)
    movdqa %xmm2, 80(%rsp)
    movdqa %xmm3, 96(%rsp)
    movdqa %xmm4, 112(%rsp)
    movdqa %xmm5, 128(%rsp)
    movdqa %xmm6, 144(%rsp)
    movdqa %xmm7, 160(%rsp)
    movq %rsp, %rdx
    call __scion_objc_forward_target
    testq %rax, %rax
    jz Lfwd_done
    movq %rax, %rdi
    movq 8(%rsp), %rsi
    movq 16(%rsp), %rdx
    movq 24(%rsp), %rcx
    movq 32(%rsp), %r8
    movq 40(%rsp), %r9
    movdqa 48(%rsp), %xmm0
    movdqa 64(%rsp), %xmm1
    movdqa 80(%rsp), %xmm2
    movdqa 96(%rsp), %xmm3
    movdqa 112(%rsp), %xmm4
    movdqa 128(%rsp), %xmm5
    movdqa 144(%rsp), %xmm6
    movdqa 160(%rsp), %xmm7
    addq $192, %rsp
    .cfi_adjust_cfa_offset -192
    popq %rax
    .cfi_adjust_cfa_offset -8
    jmp _objc_msgSend
Lfwd_done:
    .cfi_adjust_cfa_offset 200
    movq 0(%rsp), %rax
    movq 8(%rsp), %rdx
    movdqa 48(%rsp), %xmm0
    movdqa 64(%rsp), %xmm1
    addq $200, %rsp
    .cfi_adjust_cfa_offset -200
    ret
    .cfi_endproc

# __scion_objc_invoke(frame, imp, stack args, stack bytes): calls imp with the registers of a frame laid out as above,
# then stores rax, rdx, xmm0 and xmm1 back in it (NSInvocation -invoke)
    .globl __scion_objc_invoke
    .p2align 4
__scion_objc_invoke:
    .cfi_startproc
    pushq %rbp
    .cfi_adjust_cfa_offset 8
    .cfi_offset %rbp, -16
    movq %rsp, %rbp
    .cfi_def_cfa_register %rbp
    pushq %rbx
    pushq %r12
    .cfi_offset %rbx, -24
    .cfi_offset %r12, -32
    movq %rdi, %rbx
    movq %rsi, %r12
    subq %rcx, %rsp
    andq $-16, %rsp
    movq %rsp, %rdi
    movq %rdx, %rsi
    rep movsb
    movq 8(%rbx), %rsi
    movq 16(%rbx), %rdx
    movq 24(%rbx), %rcx
    movq 32(%rbx), %r8
    movq 40(%rbx), %r9
    movdqu 48(%rbx), %xmm0
    movdqu 64(%rbx), %xmm1
    movdqu 80(%rbx), %xmm2
    movdqu 96(%rbx), %xmm3
    movdqu 112(%rbx), %xmm4
    movdqu 128(%rbx), %xmm5
    movdqu 144(%rbx), %xmm6
    movdqu 160(%rbx), %xmm7
    movq 0(%rbx), %rdi
    movl $8, %eax
    call *%r12
    movq %rax, 0(%rbx)
    movq %rdx, 8(%rbx)
    movdqu %xmm0, 48(%rbx)
    movdqu %xmm1, 64(%rbx)
    leaq -16(%rbp), %rsp
    popq %r12
    popq %rbx
    popq %rbp
    .cfi_def_cfa %rsp, 8
    ret
    .cfi_endproc

    .globl __objc_msgForward_stret
__objc_msgForward_stret:
    ud2
