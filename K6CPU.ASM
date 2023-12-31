;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; K6INIT Low Level assembly functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    .model small, c
    .586p

k6_getMemorySize        PROTO C memSizeBelow16M:FAR PTR DWORD, memSizeAbove16M:FAR PTR DWORD

k6_setWriteAllocate     PROTO C whcrValue:DWORD

k6_getCPUIdentifier     PROTO C cpuidString:FAR PTR CHAR
k6_getCPUProcessorType  PROTO C

k6_toggleEPMIOBlock     PROTO C epmIoEnable:WORD
k6_setMultiplier        PROTO C multiValue:WORD

k6_setWriteOrderMode    PROTO C writeOrderMode:WORD
k6_setMTRR              PROTO C mtrrIndex:WORD, mtrrValue:DWORD

k6_getVBEInfoBlock      PROTO C vbeInfoBlockPtr:FAR PTR BYTE
k6_getVBEModeInfo       PROTO C videoMode:WORD, vbeModeInfoPtr:FAR PTR BYTE

k6_MSR_EFER             EQU 0C0000080h  ; Extended Feature Enable Register (EFER)
k6_MSR_WHCR             EQU 0C0000082h  ; Write Handling Control Register (WHCR)
k6_MSR_UWCCR            EQU 0C0000085h  ; UC/WC Cachability Control Register (UWCCR)
k6_MSR_EPMR             EQU 0C0000086h  ; Enhanced Power Management Register (EPMR)

    .CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; getMemorySize
;
; Parameters: pointer to DWORD to put the size below 16M in bytes in
;             pointer to DWORD to put the size above 16M in bytes in
; Returns: 1 in ax on success, 0 if not.

k6_getMemorySize PROC C uses ebx ecx edx es di, memSizeBelow16M:FAR PTR DWORD, memSizeAbove16M:FAR PTR DWORD

    ; Int15 call

    mov eax, 0e801h
    clc
    int 15h

    ; Carry flag set = call failed

    jc error

    ; If CX/DX are clear, use AX/BX instead

    cmp cx, 00h
    je useaxbx

    mov ax, cx
    mov bx, dx

useaxbx:

    ; At this point:
    ; AX = Mem between 1M and 16M in K
    ; BX = Mem above 16M in 64K blocks

    and eax, 0ffffh
    and ebx, 0ffffh

    ; Convert both block sizes to bytes

    shl eax, 10
    shl ebx, 16

    les di, dword ptr memSizeBelow16M
    mov dword ptr es:[di], eax
    les di, dword ptr memSizeAbove16M
    mov dword ptr es:[di], ebx

    mov eax, 1
    jp done

error:
    mov eax, 0

done:
    ret

k6_getMemorySize ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; getCPUIdentifier
;
; Reads and returns the CPU identifier string (CPUID Function Level 2)
;
; Parameters: Pointer to 12 byte memory buffer for the string.

k6_getCPUIdentifier PROC C USES eax ebx ecx edx esi, cpuidString:FAR PTR CHAR

    mov si, word ptr cpuidString

    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx

    cpuid

    mov [si+00h], ebx
    mov [si+04h], edx
    mov [si+08h], ecx

    ret

k6_getCPUIdentifier ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; getCPUProcessorType
;
; Reads and returns the processor type (CPUID Function Level 1)
;
; Returns: EAX output value from the call.

k6_getCPUProcessorType PROC C uses ebx ecx edx

    mov eax, 00000001h  ; Function Level 1: Get Processor Type, Family, etc.

    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx

    cpuid

    ret

k6_getCPUProcessorType ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; toggleEPMIOBlock
;
; Enables or disables the Enhanced Power Management (EPM) I/O block.
;
; Parameters: WORD indicating whether the block should be enabled or not.

k6_toggleEPMIOBlock PROC C uses eax ebx ecx edx, epmIoEnable:WORD

    ; Set up write to EPMR

    mov ecx, k6_MSR_EPMR
    mov edx, 0

    ; Set it up for I/O base FFF0

    mov eax, 0FFF0h

    ; Check the parameter

    cmp epmIoEnable, 0
    jz @f

    ; If we want to enable the block, set the appropriate bit

    or eax, 00001h

@@:
    wrmsr
    ret

k6_toggleEPMIOBlock ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; setMultiplier
;
; Sets the Multiplier Field in the DWORD at offset 8 of the
; EPM I/O block.
;
; Parameters: WORD containing the 3-bit value for the IBF field.
; 100b 2.0x     000b 4.5x
; 101b 3.0x     001b 5.0x
; 110b 6.0x     010b 4.0x
; 111b 3.5x     011b 5.5x

k6_setMultiplier PROC C uses eax dx, multiplierValue:WORD

    ; Requires EPMR I/O block to be active. (call toggleEPMIOBlock first)

    ; Prepare multiplier value

    mov ax, multiplierValue

    ; filter relevant bits to make sure and shift left by 5 so they
    ; fill the "Internal Bus Divisor" field

    and eax, 00007h
    shl eax, 5

    ; Set counter to force CPU into EPM stop grant state,
    ; so that the values get applied

    ; Refer to AMD-K6-2E+ Embedded Processor Data Sheet
    ; 23542A/0—September 2000 Page 147

    or eax, 01000h

    ; Set bus divisor control to 10b to set that the
    ; IBF field is sampled upon entering the EPM Stop Grant state

    or eax, 00200h

    ; Output the value to Bus Divisor and Voltage ID Control (BVC)
    ; (IOBASE + 08h)

    mov dx, 0FFF8h
    out dx, eax

    ret
k6_setMultiplier ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; setWriteOrderMode
;
; Sets the write Ordering mode using the CPU's EFER register.
;
; Parameters: WORD containing the mode (this is what ends up)
;                  in the rprocessor EFER[3] and EFER[2] bits.

k6_setWriteOrderMode PROC C uses eax ebx ecx, writeOrderMode:WORD

    ; First, read back the EFER to manipulate it

    mov ecx, k6_MSR_EFER

    ; Write back and invalidate cache

    pushf
    cli
    wbinvd

    rdmsr

    ; Mask the EWBEC bits (2 and 3), also important that we don't
    ; fault the CPU by writing reserved bits

    and eax, 0F3h

    ; prepare the EWBEC bits with the word supplied in writeOrderMode

    xor ebx, ebx
    mov bx, writeOrderMode
    shl bx, 2
    and bx, 0Ch

    or eax, ebx

    ; Write the new EFER to MSR

    mov ecx, k6_MSR_EFER
    wrmsr
    popf

    ret

k6_setWriteOrderMode ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; setWriteAllocate
;
; Parameters: DWORD containing the register value.

k6_setWriteAllocate PROC C USES eax ebx ecx edx, whcrValue:DWORD

    ; MSR register ID needs to go in ecx

    mov ecx, k6_MSR_WHCR ; Write Handling Control Register (WHCR)

    ; 31-00 = eax
    ; 63-32 = edx

    ; we only write eax since that's what we need.

    mov eax, whcrValue
    xor edx, edx

    ; since we're messing with caching stuff, we need to
    ; write back and invalidate the cache first

    pushf
    cli
    wbinvd

    ; write the WHCR value

    wrmsr
    popf

    ret
k6_setWriteAllocate ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; setMTRR
;
; Sets the MTRR of a given index to a given value. The value, including
; its bitfields must be calculated properly by the caller.
;
; Parameters: MTRR index (0 or 1)
;             MTRR value

k6_setMTRR PROC C USES eax ebx ecx edx, mtrrIndex:WORD, mtrrValue:DWORD

    ; MSR register ID needs to go in ecx

    mov ecx, k6_MSR_UWCCR ; UC/WC Cacheability Control Register (UWCCR)
    xor ebx, ebx
    mov bx, mtrrIndex

    ; First read the MSR because we only change 1 dword

    rdmsr

    ; MTRR0 = eax
    ; MTRR1 = edx

    ; if mtrrIndex = 1, then we write into edx, else eax

    cmp ebx, 0
    jnz writeMTRR1

writeMTRR0:
    mov eax, mtrrValue
    jmp @f

writeMTRR1:
    mov edx, mtrrValue

@@:
    wrmsr
    ret

k6_setMTRR ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; getVBEInfoBlock
;
; reads the VESA BIOS Extensions block from the graphics adapter
;
; Parameter: Pointer to a memory location to copy the VBE Info block to.
; Returns: Return value of the call

k6_getVBEInfoBlock PROC C USES bx cx dx es di, vbeInfoBlockPtr:FAR PTR BYTE

    les di, vbeInfoBlockPtr
    mov ax, 4f00h
    int 10h

    ; AX = Return value of the call
    ret

k6_getVBEInfoBlock ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; getVBEModeInfo
;
; reads the mode info for a given VESA mode from the VESA BIOS.
;
; Parameters: mode index
;             pointer to a memory location to copy the VBE Mode Info to.
; Returns: Return value of the call


k6_getVBEModeInfo PROC C USES bx cx dx es di, videoMode:WORD, vbeModeInfoPtr:FAR PTR BYTE

    les di, vbeModeInfoPtr
    mov ax, 4f01h
    mov cx, videoMode
    int 10h

    ; AX = Return value of the call
    ret

k6_getVBEModeInfo ENDP

    END
