{{
    ANSI / VT-100 Terminal Emulator
    Copyright (c) 2017 Marco Maccaferri and others

    TERMS OF USE: MIT License
}}

CON

    _XINFREQ = 5_000_000
    _CLKMODE = XTAL1 + PLL16X

    columns  = vga#res_x / 9
    rows     = vga#res_y / font#height
    bcnt     = columns * rows

    vgrp     = 2                                          ' video pin group
    mode     = 0                                          ' 0: FG on/off, 1: FG :==: BG

    video    = (vgrp << 9 | mode << 8 | %%333_0) << 21

    CURSOR_ON    = vga#CURSOR_ON
    CURSOR_OFF   = vga#CURSOR_OFF
    CURSOR_ULINE = vga#CURSOR_ULINE
    CURSOR_BLOCK = vga#CURSOR_BLOCK
    CURSOR_FLASH = vga#CURSOR_FLASH
    CURSOR_SOLID = vga#CURSOR_SOLID

    CURSOR_MASK  = vga#CURSOR_MASK

    #0, CM, CX, CY

    ' USB HID

    REQUEST_OUT = 0
    REQUEST_CLASS = $20
    REQUEST_TO_INTERFACE = 1

    REQ_SET_REPORT = REQUEST_OUT | REQUEST_CLASS | REQUEST_TO_INTERFACE | $0900

    REPORT_TYPE_OUTPUT = $0200

    LED_NUM_LOCK = $01
    LED_CAPS_LOCK = $02
    LED_SCROLL_LOCK = $04

VAR

    long  scrn[bcnt / 2]            ' screen buffer
    long  link[vga#res_m]           ' mailbox

    long  cursor                    ' text cursor

    long  usb_stack[128]
    byte  usb_buf[64]
    byte  usb_report[8]
    byte  usb_led

OBJ

    hc     : "usb-fs-host"
    ser    : "com.serial"
    debug  : "com.serial.terminal"
    vga    : "waitvid.80x25.driver"
    font   : "generic8x16-2font"
    kb : "keyboard"
    'keymap : "keymap_us"
    keymap : "keymap_it"
    'keymap : "keymap_uk"

PUB start | temp

    debug.Start(115200)
    ser.StartRxTx(8, 9, 0, 115200)

    wordfill(@scrn, $20_70, bcnt)
    cursor.byte[CX] := 0
    cursor.byte[CY] := 0
    cursor.byte{CM} := (cursor.byte{CM} & constant(!CURSOR_MASK)) | constant(CURSOR_ON | CURSOR_BLOCK | CURSOR_FLASH)

    link{0} := video | @scrn{0}
    link[1] := font#height << 24 | font.addr
    link[2] := @cursor
    vga.init(-1, @link{0})

    cognew(usb_hid, @usb_stack)

    temp := ser.GetMailbox
    rx_head := temp
    rx_tail := temp + 4
    rx_buffer := LONG[temp][8]

    txt_cursor := @cursor
    txt_scrn := @scrn + (bcnt << 1)

    coginit(cogid, @entry, 0)


DAT

                    org

entry
                    call    #charIn
                    cmp     ch, #$08 wz             ' backspace
        if_z        jmp     #_bs
                    cmp     ch, #$09 wz             ' tab
        if_z        jmp     #_tab
                    cmp     ch, #$0A wz             ' line feed
        if_z        jmp     #_lf
                    cmp     ch, #$0C wz             ' form feed
        if_z        jmp     #_ff
                    cmp     ch, #$0D wz             ' carriage return
        if_z        jmp     #_cr
                    cmp     ch, #$1B wz             ' esc
        if_z        jmp     #_esc

                    ' write ch to vga buffer

                    add     x, #1

                    mov     t1, y                   ' t2 := y * 80
                    shl     t1, #4
                    mov     t2, t1
                    shl     t2, #2
                    add     t2, t1
                    add     t2, x                   ' t2 := t1 + x
                    shl     t2, #1

                    mov     t1, txt_scrn
                    sub     t1, t2
                    mov     a, ch
                    shl     a, #8
                    or      a, txt_attr
                    wrword  a, t1

                    cmpsub  x, #columns wc,wz       ' wraps right
        if_nc       jmp     #_done
                    cmp     y, #rows-1 wc,wz
        if_c        add     y, #1
        if_nc       call    #scroll

_done               mov     t1, txt_cursor          ' updates cursor position
                    add     t1, #CX
                    wrbyte  x, t1
                    add     t1, #1
                    wrbyte  y, t1
                    jmp     #entry

_bs                 cmp     x, #0 wz
        if_nz       sub     x, #1
                    jmp     #_done

_tab                andn    x, #7
                    add     x, #8
                    cmpsub  x, #columns wc,wz
        if_nc       jmp     #_done
                    cmp     y, #rows-1 wc,wz
        if_c        add     y, #1
        if_nc       call    #scroll
                    jmp     #_done

_lf                 add     y, #1
                    cmp     y, #rows wc,wz
        if_nz       jmp     #_done
                    sub     y, #1
                    call    #scroll
                    jmp     #_done

_ff                 mov     x, #0
                    mov     y, #0
_cls                mov     t1, txt_scrn
                    sub     t1, #2
                    mov     t3, txt_bcnt
                    mov     a, #$20
                    shl     a, #8
                    or      a, txt_attr
:l1                 wrword  a, t1
                    sub     t1, #2
                    djnz    t3, #:l1
                    jmp     #_done

_cr                 mov     x, #0
                    jmp     #_done

_esc                mov     argc, #0
                    mov     args, #0
                    mov     args+1, #0
                    movd    :d1, #args
                    movd    :d2, #args
                    movs    :s1, #args

                    call    #charIn
                    cmp     ch, #"A" wz             ' VT-52 compatibility
        if_z        jmp     #_up
                    cmp     ch, #"B" wz
        if_z        jmp     #_down
                    cmp     ch, #"C" wz
        if_z        jmp     #_right
                    cmp     ch, #"D" wz
        if_z        jmp     #_left
                    cmp     ch, #"H" wz
        if_z        jmp     #_cup
                    cmp     ch, #"J" wz
        if_z        jmp     #_ed
                    cmp     ch, #"K" wz
        if_z        jmp     #_el
                    cmp     ch, #"7" wz
        if_z        jmp     #_save
                    cmp     ch, #"8" wz
        if_z        jmp     #_restore
                    cmp     ch, #"[" wz
        if_nz       jmp     #_done

:l2                 call    #charIn
                    cmp     ch, #"0" wc,wz
        if_c        jmp     #:l1
                    cmp     ch, #"9" wc,wz
        if_nc       jmp     #:l1
:s1                 mov     t1, 0-0                 ' multiply x 10
                    shl     t1, #1
                    mov     t2, t1
                    shl     t2, #2
                    add     t2, t1
                    sub     ch, #"0"                ' adds digit
                    add     t2, ch
:d1                 mov     0-0, t2
                    jmp     #:l2
:l1                 cmp     ch, #";" wz
        if_nz       jmp     #:l3
                    add     argc, #1
                    add     :d1, incdst
                    add     :d2, incdst
                    add     :s1, #1
:d2                 mov     0-0, #0
                    jmp     #:l2

:l3                 cmp     ch, #"A" wz
        if_z        jmp     #_up
                    cmp     ch, #"B" wz
        if_z        jmp     #_down
                    cmp     ch, #"C" wz
        if_z        jmp     #_right
                    cmp     ch, #"D" wz
        if_z        jmp     #_left
                    cmp     ch, #"H" wz
        if_z        jmp     #_cup
                    cmp     ch, #"J" wz
        if_z        jmp     #_ed
                    cmp     ch, #"K" wz
        if_z        jmp     #_el
                    cmp     ch, #"f" wz
        if_z        jmp     #_cup
                    cmp     ch, #"m" wz
        if_z        jmp     #_attr
                    cmp     ch, #"s" wz
        if_z        jmp     #_save
                    cmp     ch, #"u" wz
        if_z        jmp     #_restore

                    jmp     #_done

_up                 cmp     args, #0 wz
        if_z        add     args, #1
                    sub     y, args wc
        if_c        mov     y, #0
                    jmp     #_done

_down               cmp     args, #0 wz
        if_z        add     args, #1
                    add     y, args
                    cmp     y, #rows wc
        if_nc       mov     y, #rows-1
                    jmp     #_done

_right              cmp     args, #0 wz
        if_z        add     args, #1
                    add     x, args
                    cmp     x, #columns wc
        if_nc       mov     x, #columns-1
                    jmp     #_done

_left               cmp     args, #0 wz
        if_z        add     args, #1
                    sub     x, args wc
        if_c        mov     x, #0
                    jmp     #_done

_cup                mov     y, args
                    cmpsub  y, #1
                    mov     x, args+1
                    cmpsub  x, #1
                    jmp     #_done

_save               mov     txt_cursor_s, y
                    shl     txt_cursor_s, #16
                    or      txt_cursor_s, x
                    jmp     #_done

_restore            mov     x, txt_cursor_s
                    and     x, #$1FF
                    mov     y, txt_cursor_s
                    shr     y, #16
                    jmp     #_done

_attr               movs    :l1, #args
                    add     argc, #1

:l1                 mov     a, 0-0
                    cmp     a, #0 wz                ' reset attr
        if_z        mov     txt_attr, #$70
                    cmp     a, #1 wz                ' bright
        if_z        or      txt_attr, #$80
                    cmp     a, #5 wz                ' blink
        if_z        or      txt_attr, #$01
                    cmp     a, #30 wc               ' foreground
        if_c        jmp     #:l2
                    cmp     a, #38 wc
        if_nc       jmp     #:l2
                    sub     a, #30
                    shl     a, #4
                    and     txt_attr, #$8F
                    or      txt_attr, a
                    jmp     #:l3
:l2                 cmp     a, #40 wc               ' background
        if_c        jmp     #:l4
                    cmp     a, #48 wc
        if_nc       jmp     #:l4
                    sub     a, #40
                    shl     a, #1
                    and     txt_attr, #$F1
                    or      txt_attr, a
                    jmp     #:l3
:l4                 cmp     a, #39 wz               ' reset foreground
        if_z        and     txt_attr, #$0F
        if_z        or      txt_attr, #$70
                    cmp     a, #49 wz               ' reset background
        if_z        and     txt_attr, #$F1

:l3                 add     :l1, #1
                    djnz    argc, #:l1
                    jmp     #_done

_ed                 cmp     args, #2 wz             ' clear entire screen
        if_z        jmp     #_cls

                    mov     t1, y                   ' t2 := y * 80
                    shl     t1, #4
                    mov     t2, t1
                    shl     t2, #2
                    add     t2, t1
                    add     t2, x                   ' t2 := t2 + x
                    mov     t1, txt_scrn
                    sub     t1, t2
                    sub     t1, t2                  ' t1 := pointer to cursor location

                    mov     a, #$20
                    shl     a, #8
                    or      a, txt_attr

                    cmp     args, #1 wz
        if_z        jmp     #:ed1
                    cmp     args, #0 wz
        if_z        jmp     #:ed0
                    jmp     #_done
:ed0                mov     t3, txt_bcnt
                    sub     t3, t2
                    sub     t1, #2                  ' clear screen from cursor down
                    wrword  a, t1
                    djnz    t3, #$-2
                    jmp     #_done
:ed1                mov     t3, t2                  ' clear screen from cursor up
                    add     t3, #1
                    sub     t1, #2
                    wrword  a, t1
                    add     t1, #2
                    djnz    t3, #$-2
                    jmp     #_done

_el                 mov     t1, y                   ' t1 := y * 80
                    shl     t1, #4
                    mov     t2, t1
                    shl     t2, #2
                    add     t2, t1
                    mov     t1, txt_scrn
                    sub     t1, t2
                    sub     t1, t2                  ' t1 := pointer to begin of line at cursor

                    mov     a, #$20
                    shl     a, #8
                    or      a, txt_attr

                    cmp     args, #0 wz
        if_z        jmp     #:el0
                    cmp     args, #1 wz
        if_z        jmp     #:el1
                    cmp     args, #2 wz
        if_z        jmp     #:el2
                    jmp     #_done
:el0                sub     t1, x                   ' clear line from cursor right
                    sub     t1, x
                    mov     t3, #columns
                    sub     t3, x
                    sub     t1, #2
                    wrword  a, t1
                    djnz    t3, #$-2
                    jmp     #_done
:el1                mov     t3, x                   ' clear line from cursor left
                    add     t3, #1
                    sub     t1, #2
                    wrword  a, t1
                    djnz    t3, #$-2
                    jmp     #_done
:el2                mov     t3, #columns            ' clear entire line
                    sub     t1, #2
                    wrword  a, t1
                    djnz    t3, #$-2
                    jmp     #_done

' Receive single-byte character. Waits until character received.
'
' Returns: $00..$FF in ch

charIn              rdlong  t1, rx_head
                    rdlong  t2, rx_tail
                    cmp     t1, t2 wz
        if_z        jmp     #$-3
                    mov     t1, rx_buffer
                    add     t1, t2
                    rdbyte  ch, t1
                    add     t2, #1
                    and     t2, #ser#BUFFER_MASK
                    wrlong  t2, rx_tail
charIn_ret          ret

' Scrolls entire screen one row up

scroll              mov     t1, txt_scrn
                    sub     t1, #2
                    mov     t2, t1
                    sub     t2, #columns << 1
                    mov     t3, txt_bcnt
                    sub     t3, #columns
:l1                 rdword  a, t2
                    sub     t2, #2
                    wrword  a, t1
                    sub     t1, #2
                    djnz    t3, #:l1

                    mov     a, #$20
                    shl     a, #8
                    or      a, txt_attr
                    mov     t3, #columns
:l2                 wrword  a, t1
                    sub     t1, #2
                    djnz    t3, #:l2

scroll_ret          ret

incdst              long    1 << 9

rx_buffer           long    0
rx_head             long    0
rx_tail             long    0

txt_cursor          long    0
txt_scrn            long    0
txt_bcnt            long    bcnt
txt_attr            long    $70
txt_cursor_s        long    0

x                   long    0
y                   long    0

a                   res     1
ch                  res     1
t1                  res     1
t2                  res     1
t3                  res     1

argc                res     1
args                res     8

                    fit

PUB usb_hid | retval, ifd, epd

    debug.str(string(debug#CS, "USB Started", debug#NL, debug#LF))

    repeat
        if showError(\hc.Enumerate, string("Can't enumerate device"))
            waitcnt(CNT + CLKFREQ)
            next

        debug.str(string("Found device "))
        debug.hex(hc.VendorID, 4)
        debug.char(":")
        debug.hex(hc.ProductID, 4)
        debug.str(string(debug#NL, debug#LF))

        if showError(\hc.Configure, string("Error configuring device"))
            waitcnt(CNT + CLKFREQ)
            next

        if not (ifd := hc.FindInterface(3))
            debug.str(string("Device has no HID interfaces", debug#NL, debug#LF))
            waitcnt(CNT + CLKFREQ)
            next

        ' First endpoint on the first HID interface
        epd := hc.NextEndpoint(ifd)

        ' Blink LEDs
        usb_led := LED_NUM_LOCK|LED_CAPS_LOCK|LED_SCROLL_LOCK
        hc.ControlWrite(REQ_SET_REPORT, REPORT_TYPE_OUTPUT, 0, @usb_led, 1)
        waitcnt(CNT + CLKFREQ / 2)
        usb_led := 0
        hc.ControlWrite(REQ_SET_REPORT, REPORT_TYPE_OUTPUT, 0, @usb_led, 1)

        repeat while hc.GetPortConnection <> hc#PORTC_NO_DEVICE
            retval := \hc.InterruptRead(epd, @usb_buf, 64)

            if retval == hc#E_TIMEOUT
                ' No data available. Try again later.

            elseif not showError(retval, string("Read Error"))
                ' Successful transfer
                'debug.char("[")
                'debug.dec(retval)
                'debug.str(string(" bytes] "))
                'hexDump(@usb_buf, retval)
                decode(@usb_buf)
                'debug.str(string(debug#NL, debug#LF))

        waitcnt(CNT + CLKFREQ)

PRI decode(buffer) | i, c, k, mod, ptr

    usb_report[0] := BYTE[buffer][0]
    usb_report[1] := BYTE[buffer][1]

    if (usb_report[0] & %00100010) <> 0         ' SHIFT
        if (usb_report[0] & %01000000) <> 0     ' SHIFT+ALT GR ?
            mod := 3
        else
            mod := 1
    elseif (usb_report[0] & %01000000) <> 0     ' ALT GR
        mod := 2
    else
        mod := 0

    repeat i from 2 to 7
        k := BYTE[buffer][i]
        if k <> 0 and lookdown(k : usb_report[2], usb_report[3], usb_report[4], usb_report[5], usb_report[6], usb_report[7]) == 0
            if (usb_led & LED_NUM_LOCK) and k => $59 and k =< $63
                c := keymap.map(k, 1)
            else
                c := keymap.map(k, mod)
            case c
                "A".."Z":
                    if (usb_report[0] & %00010001) ' CTRL
                        ser.char(c - "A" + 1)
                    else
                        ser.char(c)
                "a".."z":
                    if (usb_report[0] & %00010001) ' CTRL
                        ser.char(c - "a" + 1)
                    elseif (usb_led & LED_CAPS_LOCK)
                        ser.char(c ^ $20)
                    else
                        ser.char(c)
                0..$FF:
                    ser.char(c)

                kb#KeyNumLock:
                    usb_led ^= LED_NUM_LOCK
                    hc.ControlWrite(REQ_SET_REPORT, REPORT_TYPE_OUTPUT, 0, @usb_led, 1)
                kb#KeyCapsLock:
                    usb_led ^= LED_CAPS_LOCK
                    hc.ControlWrite(REQ_SET_REPORT, REPORT_TYPE_OUTPUT, 0, @usb_led, 1)
                kb#KeyScrollLock:
                    usb_led ^= LED_SCROLL_LOCK
                    hc.ControlWrite(REQ_SET_REPORT, REPORT_TYPE_OUTPUT, 0, @usb_led, 1)

                kb#KeySpace..kb#KeyMaxCode:
                    ptr := @@strTable[c - kb#KeySpace]
                    repeat strsize(ptr)
                        ser.char(byte[ptr])
                        ptr++

        usb_report[i] := k

PRI decodeDebug(buffer)

    hexDump(buffer, 8)
    debug.char(debug#NL)

    decode(buffer)

    debug.char(debug#NL)


PRI hexDump(buffer, len)
    repeat while len--
        debug.hex(BYTE[buffer++], 2)
        debug.char(" ")

PRI showError(error, message) : bool
    if error < 0
        debug.str(message)
        debug.str(string(" (Error "))
        debug.dec(error)
        debug.str(string(")", debug#NL))
        return 1
    return 0

DAT

strTable            word    @strKeySpace
                    word    @strKeyEscape
                    word    @strKeyBackspace
                    word    @strKeyTabulator
                    word    @strKeyReturn
                    word    @strKeyInsert
                    word    @strKeyHome
                    word    @strKeyPageUp
                    word    @strKeyDelete
                    word    @strKeyEnd
                    word    @strKeyPageDown
                    word    @strKeyUp
                    word    @strKeyDown
                    word    @strKeyLeft
                    word    @strKeyRight
                    word    @strKeyF1
                    word    @strKeyF2
                    word    @strKeyF3
                    word    @strKeyF4
                    word    @strKeyF5
                    word    @strKeyF6
                    word    @strKeyF7
                    word    @strKeyF8
                    word    @strKeyF9
                    word    @strKeyF10
                    word    @strKeyF11
                    word    @strKeyF12
                    word    @strKeyApplication
                    word    @strKeyCapsLock
                    word    @strKeyPrintScreen
                    word    @strKeyScrollLock
                    word    @strKeyPause
                    word    @strKeyNumLock
                    word    @strKeyKP_Divide
                    word    @strKeyKP_Multiply
                    word    @strKeyKP_Subtract
                    word    @strKeyKP_Add
                    word    @strKeyKP_Enter
                    word    @strKeyKP_1
                    word    @strKeyKP_2
                    word    @strKeyKP_3
                    word    @strKeyKP_4
                    word    @strKeyKP_5
                    word    @strKeyKP_6
                    word    @strKeyKP_7
                    word    @strKeyKP_8
                    word    @strKeyKP_9
                    word    @strKeyKP_0
                    word    @strKeyKP_Center
                    word    @strKeyKP_Comma
                    word    @strKeyKP_Period

strKeySpace         byte    " ", 0
strKeyEscape        byte    $1B, 0
strKeyBackspace     byte    $08, 0
strKeyTabulator     byte    $09, 0
strKeyReturn        byte    $0D, 0
strKeyInsert        byte    0
strKeyHome          byte    $1B, "[H", 0
strKeyPageUp        byte    0
strKeyDelete        byte    $7F, 0
strKeyEnd           byte    $1B, "[K", 0
strKeyPageDown      byte    0
strKeyUp            byte    $1B, "OA", 0
strKeyDown          byte    $1B, "OB", 0
strKeyLeft          byte    $1B, "OD", 0
strKeyRight         byte    $1B, "OC", 0
strKeyF1            byte    $1B, "OP", 0
strKeyF2            byte    $1B, "OQ", 0
strKeyF3            byte    $1B, "OR", 0
strKeyF4            byte    $1B, "OS", 0
strKeyF5            byte    $1B, "OT", 0
strKeyF6            byte    $1B, "OU", 0
strKeyF7            byte    $1B, "OV", 0
strKeyF8            byte    $1B, "OW", 0
strKeyF9            byte    $1B, "OX", 0
strKeyF10           byte    $1B, "OY", 0
strKeyF11           byte    0
strKeyF12           byte    0
strKeyApplication   byte    0
strKeyCapsLock      byte    0
strKeyPrintScreen   byte    0
strKeyScrollLock    byte    0
strKeyPause         byte    0
strKeyNumLock       byte    0
strKeyKP_Divide     byte    "/", 0
strKeyKP_Multiply   byte    "*", 0
strKeyKP_Subtract   byte    "-", 0
strKeyKP_Add        byte    "+", 0
strKeyKP_Enter      byte    $0D, 0
strKeyKP_1          byte    "1", 0
strKeyKP_2          byte    "2", 0
strKeyKP_3          byte    "3", 0
strKeyKP_4          byte    "4", 0
strKeyKP_5          byte    "5", 0
strKeyKP_6          byte    "6", 0
strKeyKP_7          byte    "7", 0
strKeyKP_8          byte    "8", 0
strKeyKP_9          byte    "9", 0
strKeyKP_0          byte    "0", 0
strKeyKP_Center     byte    0
strKeyKP_Comma      byte    ",", 0
strKeyKP_Period     byte    ".", 0

{{

 TERMS OF USE: MIT License

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
 associated documentation files (the "Software"), to deal in the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
 following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial
 portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
 LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

}}
