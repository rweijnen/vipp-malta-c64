; ---------------------------------------------------------------------------
; VIPP Malta 2026 - a small C64 demo (PAL)
;
;   * Graffiti VIPP logo made of 24 multicolor sprites (3 rows x 8): sine
;     sweep left/right, gravity bounce up/down, colour shine across it
;   * 2x2 multicolor scroller (Ocean style gold) greeting all VIPP members
;   * Music: Commando by Rob Hubbard (HVSC)
;
; Assemble with 64tass:  64tass -B -o build/vipp.prg src/main.asm
; ---------------------------------------------------------------------------

            .include "../build/tables.inc"

            .weak
DEBUG       = 0                 ; 64tass -D DEBUG=1: border shows IRQ raster time
            .endweak

; --- memory map (VIC bank 0, $0000-$3fff) ---------------------------------
CHARSET     = $2000             ; 2x2 multicolor font (build/font.bin)
SCR_A       = $2800             ; screen: text + sprite ptrs for logo row 1
SCR_B       = $2c00             ; sprite ptrs for logo row 2 (text unused)
SCR_C       = $3000             ; sprite ptrs for logo row 3 (text unused)
SPRITES     = $3400             ; 24 logo sprites ($3400-$39ff)
IDLE_BYTE   = $3fff             ; VIC idle-state graphics (shown in FLD area)
SID_LOAD    = $5000
SID_INIT    = $5fb2
SID_PLAY    = $5012
SONG        = 0                 ; first sub tune: the main theme

D018_A      = ((SCR_A & $3fff) / $400) << 4 | ((CHARSET & $3fff) / $800) << 1
D018_B      = ((SCR_B & $3fff) / $400) << 4 | ((CHARSET & $3fff) / $800) << 1
D018_C      = ((SCR_C & $3fff) / $400) << 4 | ((CHARSET & $3fff) / $800) << 1
SPR_PTR0    = (SPRITES & $3fff) / 64

BLANK       = 32 * 4            ; top-left quarter of the 2x2 space glyph

TITLE_ROW   = 1                 ; title: screen rows 1-2, raster lines 59-74
SCROLL_SPEED = 2                ; pixels per frame
X_SPEED     = $80               ; x sine phase step per frame (8.8): 512 frames

; Raster layout. Lines 72-225 are an FLD area: YSCROLL is kept ahead of the
; raster so no badline ever happens there. The CPU is never stalled for 40
; cycles, so the sprite row swaps work at any logo Y. Because screen rows 3+
; are pushed down, the char row after the FLD area (line 227) shows screen
; row 3: that is where the scroller lives.
KERNEL_LINE = 72                ; IRQ that runs the FLD / multiplex loop
FLD_END     = 225               ; last line of the loop, YSCROLL back to 3
SCROLL_ROW  = 3                 ; screen rows 3-4, shown on lines 227-242
IRQ_BOTTOM_LINE = 245           ; music, movement, scroller, colours

; --- BASIC stub: 2026 SYS2061 -----------------------------------------------
            * = $0801
            .word (+), 2026
            .null $9e, format("%d", start)
+           .word 0

; ---------------------------------------------------------------------------
start
            sei
            jsr detect_pal
            bcs pal_ok
            ; NTSC (or unknown) machine: say so clearly and stop.
            ldx #0
-           lda ntsc_msg,x
            beq +
            jsr $ffd2
            inx
            bne -
+           cli
            jmp *

pal_ok
            lda #$7f            ; no CIA interrupts
            sta $dc0d
            sta $dd0d
            lda $dc0d
            lda $dd0d

            lda #0
            sta $d01a           ; no VIC irqs yet
            sta $d015           ; sprites off while building
            sta $d020
            sta $d021

            lda #$35            ; RAM everywhere except I/O
            sta $01
            lda #0
            sta IDLE_BYTE

            lda #<nmi           ; RESTORE key does nothing
            sta $fffa
            lda #>nmi
            sta $fffb
            lda #<irq_bottom
            sta $fffe
            lda #>irq_bottom
            sta $ffff

            lda $dd00           ; VIC bank 0
            ora #%00000011
            sta $dd00

            jsr clear_screens
            jsr draw_title
            jsr setup_sprites

            lda #$1b
            sta $d011
            lda #$d8            ; 40 columns, multicolor text
            sta $d016
            lda #FONT_C1        ; font %01 / %10 colours
            sta $d022
            lda #FONT_C2
            sta $d023
            lda #D018_A
            sta $d018

            lda #SONG
            jsr SID_INIT

            lda #IRQ_BOTTOM_LINE
            sta $d012
            lda #1
            sta $d01a
            lda #$ff
            sta $d019
            cli
            jmp *

nmi         rti

; ---------------------------------------------------------------------------
; Carry set = PAL (312 lines). Waits until the raster counter wraps and looks
; at the last line number before the wrap: $37 (311) on PAL, $05/$06 on NTSC.
detect_pal
-           lda $d012
-           cmp $d012
            beq -
            bmi --
            cmp #$30
            rts

ntsc_msg    .null 13, "THIS DEMO NEEDS A PAL C64.", 13, "PLEASE SWITCH THE VIDEO MODE TO PAL", 13, "AND RUN IT AGAIN.", 13

; ---------------------------------------------------------------------------
clear_screens
            ldx #0
-           lda #BLANK
            sta SCR_A,x
            sta SCR_A+$100,x
            sta SCR_A+$200,x
            sta SCR_A+$300,x
            sta SCR_B,x
            sta SCR_B+$100,x
            sta SCR_B+$200,x
            sta SCR_B+$300,x
            sta SCR_C,x
            sta SCR_C+$100,x
            sta SCR_C+$200,x
            sta SCR_C+$300,x
            inx
            bne -
            ; colour RAM of the 2x2 text rows: multicolor (bit 3) + gradient
            ; colour of the top / bottom half of the glyphs
            ldx #39
-           lda #FONT_TOP | 8
            sta $d800 + TITLE_ROW * 40,x
            sta $d800 + SCROLL_ROW * 40,x
            lda #FONT_BOTTOM | 8
            sta $d800 + (TITLE_ROW + 1) * 40,x
            sta $d800 + (SCROLL_ROW + 1) * 40,x
            dex
            bpl -
            rts

; Title in 2x2 chars (only screen A is ever displayed outside the FLD area)
TITLE_COL   = (40 - 2 * title_len) / 2
draw_title
            ldx #0
            ldy #TITLE_COL
-           lda title,x
            asl a
            asl a
            sta SCR_A + TITLE_ROW * 40,y
            ora #1
            sta SCR_A + TITLE_ROW * 40 + 1,y
            ora #2
            sta SCR_A + (TITLE_ROW + 1) * 40 + 1,y
            and #$fe
            sta SCR_A + (TITLE_ROW + 1) * 40,y
            iny
            iny
            inx
            cpx #title_len
            bne -
            rts

; ---------------------------------------------------------------------------
setup_sprites
            ldx #0
-           txa
            clc
            adc #SPR_PTR0
            sta SCR_A + $3f8,x
            adc #8
            sta SCR_B + $3f8,x
            adc #8
            sta SCR_C + $3f8,x
            inx
            cpx #8
            bne -
            lda #COL_LIGHT      ; %01 pixels: highlights
            sta $d025
            lda #COL_OUTLINE    ; %11 pixels: outline + drop shadow
            sta $d026
            ldx #BAR_SPRITES - 1
-           lda #COL_BAR        ; %10 pixels: body, per sprite column
            sta $d027,x
            dex
            bpl -
            jsr shine_logo      ; letter columns
            lda #$ff
            sta $d01c           ; all multicolor
            lda #0
            sta $d017
            sta $d01d
            sta $d01b           ; sprites in front of text
            jsr position_logo
            lda #$ff
            sta $d015
            rts

; Advance the motion and set X/Y of all 8 sprites for logo row 1. Also
; computes the raster lines the FLD loop acts on for rows 2 and 3.
next_position
            lda x_phase
            clc
            adc #X_SPEED
            sta x_phase
            bcc +
            inc x_idx
+           ldx y_idx
            inx
            cpx #Y_LEN
            bne +
            ldx #0
+           stx y_idx
            ; fall through

position_logo
            ldx y_idx
            lda bounce_y,x
            sta cur_y
            ; kernel events, in raster order (see irq_kernel)
            clc
            adc #8
            sta ev_line+0       ; y+8: row 1 has started, load row 2 Y
            adc #13
            sta ev_line+1       ; y+21: last line of row 1 -> row 2 pointers
            sta ev_yval+0
            adc #9
            sta ev_line+2       ; y+30: load row 3 Y
            adc #12
            sta ev_line+3       ; y+42: last line of row 2 -> row 3 pointers
            sta ev_yval+2
            ldx x_idx
            lda bounce_x,x
            sta x_lo
            lda bounce_xhi,x
            sta x_hi
            lda #0
            sta msb
            ldy #0
-           lda x_lo
            sta $d000,y
            lda cur_y
            sta $d001,y
            lda x_hi
            lsr a
            ror msb
            lda x_lo
            clc
            adc #24
            sta x_lo
            bcc +
            inc x_hi
+           iny
            iny
            cpy #16
            bne -
            lda msb
            sta $d010
            rts

; ---------------------------------------------------------------------------
; IRQ chain: kernel (line 72) -> bottom (line 245) -> kernel ...
; ---------------------------------------------------------------------------
irq_bottom
            pha
            txa
            pha
            tya
            pha
.if DEBUG != 0
            lda #5
            sta $d020
.endif
            lda #$d8            ; 40 columns, multicolor, no fine scroll
            sta $d016

            jsr SID_PLAY
            jsr next_position
            jsr update_scroller
            jsr shine_logo

            lda #KERNEL_LINE
            sta $d012
            lda #<irq_kernel
            sta $fffe
            lda #>irq_kernel
            sta $ffff
            jmp irq_exit

; Runs every raster line from KERNEL_LINE to FLD_END:
;  * keeps YSCROLL one line behind the raster (= 7 ahead), so no badline can
;    happen in this area even if an iteration runs a few lines late (FLD)
;  * works through the event list ev_line (raster order, "at or past" test,
;    so a skipped line never loses an event):
;      even events move the 8 sprites down to the next logo row
;      odd events switch screen, which swaps all 8 sprite pointers at once.
;      That must happen early in the line: after the last pointer fetch of
;      the row above (cycle ~10), before the first fetch of the next row
;      (cycle 58).
; A normal iteration is ~30 cycles, below the 44 the CPU gets on a line with
; 8 sprites, so the loop keeps up with the raster.
irq_kernel
            pha
            txa
            pha
            tya
            pha
.if DEBUG != 0
            lda #2
            sta $d020
.endif
            ldy #0              ; next event
            ldx $d012
            jmp _fld
_wait
-           cpx $d012
            beq -
            ldx $d012
            txa
            cmp ev_line,y
            bcc _fld
            lda ev_d018,y
            beq _sety
            sta $d018
            iny
            bne _fld            ; always
_sety       lda ev_yval,y
            jsr set_sprite_y
            iny
_fld        lda fld_d011,x
            sta $d011
            cpx #FLD_END
            bcc _wait
            lda #$1b            ; YSCROLL 3: badline (scroller row) at 227
            sta $d011
            lda #D018_A
            sta $d018
            lda xscroll         ; 38 columns + fine scroll for the scroller
            ora #$10            ; multicolor text
            sta $d016

            lda #IRQ_BOTTOM_LINE
            sta $d012
            lda #<irq_bottom
            sta $fffe
            lda #>irq_bottom
            sta $ffff

irq_exit
.if DEBUG != 0
            lda #0
            sta $d020
.endif
            lda #$ff
            sta $d019
            pla
            tay
            pla
            tax
            pla
            rti

; $d011 value for raster line n in the FLD area: YSCROLL = (n - 1) & 7
            .align 256
fld_d011
            .for n = 0, n < 256, n += 1
            .byte $18 | ((n + 7) & 7)
            .next

set_sprite_y
            sta $d001
            sta $d003
            sta $d005
            sta $d007
            sta $d009
            sta $d00b
            sta $d00d
            sta $d00f
            rts

; ---------------------------------------------------------------------------
SROW1       = SCR_A + SCROLL_ROW * 40
SROW2       = SCR_A + (SCROLL_ROW + 1) * 40

update_scroller
            lda xscroll
            sec
            sbc #SCROLL_SPEED
            bmi +
            sta xscroll
            rts
+           and #7
            sta xscroll
            ldx #0
-           lda SROW1+1,x
            sta SROW1,x
            lda SROW2+1,x
            sta SROW2,x
            inx
            cpx #39
            bne -
            lda half
            bne _right
_text       lda scrolltext      ; operand is the text pointer (self-modified)
            cmp #$ff
            bne +
            lda #<scrolltext
            sta _text+1
            lda #>scrolltext
            sta _text+2
            jmp _text
+           sta cur_char
            inc _text+1
            bne +
            inc _text+2
+           lda cur_char
            asl a
            asl a
            sta SROW1+39
            ora #2
            sta SROW2+39
            lda #1
            sta half
            rts
_right      lda cur_char
            asl a
            asl a
            ora #1
            sta SROW1+39
            ora #2
            sta SROW2+39
            lda #0
            sta half
            rts

; A bright shine sweeping left to right over the letters, one colour per
; letter sprite column (each column is 24 pixels wide). Bars keep their colour.
shine_logo
            inc shine_phase
            lda shine_phase
            lsr a
            sta shine_tmp
            ldx #BAR_SPRITES
-           lda shine_tmp
            and #63
            tay
            lda shine,y
            sta $d027,x
            lda shine_tmp
            sec
            sbc #3
            sta shine_tmp
            inx
            cpx #8
            bne -
            rts

shine       .fill 51, COL_LETTER           ; 64 entries: letter colour with a
            .byte $03,$03,$0d,$01,$01,$01,$0d,$03,$03 ; cyan/white glint
            .fill 4, COL_LETTER

; --- variables -----------------------------------------------------------------
x_phase     .byte 0
x_idx       .byte 0
y_idx       .byte 0
cur_y       .byte 0
ev_line     .byte 0, 0, 0, 0, $ff  ; raster lines of the kernel events, $ff = end
ev_d018     .byte 0, D018_B, 0, D018_C ; odd events: new $d018 (sprite pointers)
ev_yval     .byte 0, 0, 0, 0           ; even events: new sprite Y
x_lo        .byte 0
x_hi        .byte 0
msb         .byte 0
xscroll     .byte 7
half        .byte 0
cur_char    .byte 32
shine_phase .byte 0
shine_tmp   .byte 0

; --- generated data ------------------------------------------------------------
            .align 256
bounce_x    .binary "../build/bounce_x.bin"
bounce_xhi  .binary "../build/bounce_xhi.bin"
bounce_y    .binary "../build/bounce_y.bin"
title       .binary "../build/title.bin"
title_len   = * - title
scrolltext  .binary "../build/scrolltext.bin"
code_end
            .cerror code_end > CHARSET, "code/data overlaps the charset at ", CHARSET

            * = CHARSET
            .binary "../build/font.bin"
            .cerror * > SCR_A, "charset overlaps screen A"

            * = SPRITES
            .binary "../build/logo_sprites.bin"
            .cerror * > IDLE_BYTE, "sprites overlap the VIC idle byte"

            * = SID_LOAD
            .binary "../assets/Commando.sid", $7e
            .cerror * != $5fc7, "unexpected Commando.sid size"
