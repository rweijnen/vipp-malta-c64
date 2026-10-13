; ---------------------------------------------------------------------------
; VIPP Malta 2026 - a small C64 demo (PAL)
;
;   * VIPP logo made of 21 multicolor sprites (sprites 1-7, 3 rows): sine
;     sweep left/right, gravity bounce up/down, colour shine across it
;   * '10' for the 10 year anniversary (sprite 0, hires, 24x42), bouncing
;     off the screen edges on its own, in front of everything
;   * when the 10 bumps into the VIPP logo, both freeze (the logo trembles),
;     the 10 recoils just clear of the logo, a laser gun slides in and shoots
;     it three times, and the 10 shatters in a multicolor fire explosion
;     (screen flash, logo shake, the logo glows in the fire colours). The gun
;     borrows sprite 7 above or below the logo. The beam is cut exactly at
;     the 10 with a CIA timer synced to the raster.
;   * 2x2 multicolor scroller (Ocean style gold) greeting all VIPP members,
;     with a rippling water reflection below it
;   * Music: Commando by Rob Hubbard (HVSC). Its SID writes go through
;     small stubs, so voice 3 (the drums) can be borrowed for the laser and
;     explosion sound effects, as games did
;
; Assemble with 64tass:  64tass -B -o build/vipp.prg src/main.asm
; ---------------------------------------------------------------------------

            .include "../build/tables.inc"

            .weak
DEBUG       = 0                 ; 64tass -D DEBUG=1: border shows IRQ raster time
SYNC_TEST   = 0                 ; 64tass -D SYNC_TEST=1: repeat the timer sync
MUSIC_DIRECT = 0                ; 64tass -D MUSIC_DIRECT=1: original player, no effects
SFX_OFF     = 0                 ; 64tass -D SFX_OFF=1: stubs but no effects (test)
            .endweak

; --- memory map (VIC bank 0, $0000-$3fff) ---------------------------------
CHARSET     = $2000             ; 2x2 multicolor font (build/font.bin)
SCR_A       = $2800             ; screen: text + sprite ptrs for logo row 1
SCR_B       = $2c00             ; sprite ptrs for logo row 2 (text unused)
SCR_C       = $3000             ; sprite ptrs for logo row 3 (text unused)
SPRITES     = $3400             ; 24 sprite blocks ($3400-$39ff), see gen_assets
EXPLOSION   = $3a00             ; EXPL_FRAMES explosion sprite frames
GUN         = EXPLOSION + EXPL_FRAMES * 64      ; laser gun: idle, firing
IDLE_BYTE   = $3fff             ; VIC idle-state graphics (shown in FLD area)
SID_LOAD    = $5000
SID_INIT    = $5fb2
SID_PLAY    = $5012
SONG        = 0                 ; first sub tune: the main theme
SID_STUBS   = $6600             ; SID write stubs for the player (music.inc)
SID_SHADOW  = $6f00             ; copy of the music's SID registers

D018_A      = ((SCR_A & $3fff) / $400) << 4 | ((CHARSET & $3fff) / $800) << 1
D018_B      = ((SCR_B & $3fff) / $400) << 4 | ((CHARSET & $3fff) / $800) << 1
D018_C      = ((SCR_C & $3fff) / $400) << 4 | ((CHARSET & $3fff) / $800) << 1
SPR_PTR0    = (SPRITES & $3fff) / 64
EXPL_PTR0   = (EXPLOSION & $3fff) / 64
GUN_PTR     = (GUN & $3fff) / 64

BLANK       = 0                 ; glyph 0 is the space: chars 0-3 are blank

TITLE_ROW   = 1                 ; title: screen rows 1-2, raster lines 59-74
SCROLL_SPEED = 2                ; pixels per frame
X_SPEED     = $80               ; x sine phase step per frame (8.8): 512 frames
TEN_YSPEED  = $c0               ; '10' moves 1 px/frame in X, 0.75 px/frame in Y

EXPL_SPEED  = 3                 ; video frames per explosion frame
COOL_FRAMES = 100               ; frames without a new bump after an attack (2 s)
FLASH_LEN   = 6                 ; background flash frames
SHAKE_LEN   = 24                ; logo shake frames after an explosion
; The attack (see update_effects)
ATK_IDLE    = 0
ATK_RECOIL  = 1                 ; both frozen, the 10 moves just clear of VIPP
ATK_GUN_IN  = 2                 ; the gun slides in
ATK_SHOOT   = 3                 ; 3 shots
ATK_BOOM    = 4                 ; the 10 explodes, the gun slides out
GUN_COL     = 15                ; light grey
SHOTS       = 3
SHOT_LEN    = 12                ; frames per shot (6 beam + 6 pause)
HIT_FRAMES  = 4                 ; the 10 flashes light red when hit
TEN_BEAM    = 21                ; the beam hits the 10 on line ten_y + 21
RECOIL_MIN  = 16                ; the bump knocks the 10 back at least this far
GUN_ABOVE_Y = TEN_BEAM - 1 - 2 * GUN_MUZZLE_ABOVE   ; gun_y - ten_y
GUN_BELOW_Y = TEN_BEAM - 1 - 2 * GUN_MUZZLE_BELOW
GUN_L_IN    = 24                ; gun X when fully in, at the left edge
GUN_R_IN    = 344 - 48          ; ... at the right edge
GUN_R_OUT   = 344               ; hidden in the right border
; horizontal limits for the 10 so the beam cut has enough cycles (see
; beam_event); the recoil moves it inside if needed
TEN_X_LGUN  = 298               ; gun left: the 10 at most here
TEN_X_RGUN  = 70                ; gun right: the 10 at least here
CUT_LEFT    = 6                 ; beam ends this many px into the 10 (gun left)
CUT_RIGHT   = 18                ; beam starts here in the 10 (gun right)
; beam timing calibration (measured in VICE, see beam_event)
BEAM_K0     = 98                ; sync step: w0 on cycle 12 (measured)
BEAM_KA     = 86                ; steps of (Wc - 12) cycles: k = KA - Wc
BEAM_KB     = 9                 ; steps of (75 - Wc) cycles: k = KB + Wc
BEAM_XC     = 14                ; cut cycle Wc = (x >> 3) + XC
BEAM_WMIN   = 25
BEAM_WMAX   = 52

EV_SWAP     = 0                 ; kernel event kinds, see irq_kernel
EV_BEAM     = 1
EV_Y        = 2
EV_GUN_OFF  = 3
EV_GUN_ON   = 4

; Raster layout. Lines 72-225 are an FLD area: YSCROLL is kept ahead of the
; raster so no badline ever happens there. The CPU is never stalled for 40
; cycles, so the sprite row swaps work at any logo Y. Because screen rows 3+
; are pushed down, the char row after the FLD area (line 227) shows screen
; row 3: that is where the scroller lives.
KERNEL_LINE = 72                ; IRQ that runs the FLD / multiplex loop
FLD_END     = 225               ; last line of the loop, YSCROLL back to 3
SCROLL_ROW  = 3                 ; screen rows 3-4, shown on lines 227-242
REFL_ROW    = SCROLL_ROW + 2    ; the reflection: screen row 5, lines 243-250
IRQ_BOTTOM_LINE = 242           ; ripple, then music, movement, scroller...
RIPPLE_LINE = 244               ; first rippled line (243 is a badline)

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

            jsr sync_timer      ; CIA timer in lock step with the raster
.if SYNC_TEST != 0
            ; test: sync again with every possible start jitter; sync_point
            ; must always run on the same raster cycle
            ldy #0
-           tya
            jsr delay_a_small
            jsr sync_timer
            iny
            cpy #8
            bne -
.endif
            lda #<irq_bottom
            sta $fffe
            lda #>irq_bottom
            sta $ffff

            ldx #24             ; the SID copy starts like a reset SID: the
            lda #0              ; player never writes some registers (filter)
-           sta SID_SHADOW,x
            dex
            bpl -
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
; CIA 1 timer A counts 62..0 over and over: 63 cycles, exactly one PAL raster
; line. It is started from a stable raster (double IRQ), so its value tells
; the exact cycle within a line. The kernel uses it to cut the laser beam at
; the 10 with single cycle precision. (Its interrupt stays disabled.)
SYNC_LINE   = 20                ; in the top border: no badlines, no sprites

sync_timer
            lda #<sync_irq1
            sta $fffe
            lda #>sync_irq1
            sta $ffff
            lda #SYNC_LINE
            sta $d012
            lda #$1b
            sta $d011
            lda #1
            sta $d01a
            sta $d019
            lda #0
            sta synced
            cli
-           lda synced
            beq -
            sei
            lda #0
            sta $d01a
            lda #$ff
            sta $d019
            rts

sync_irq1                       ; entered with 0-7 cycles of jitter
            lda #<sync_irq2
            sta $fffe
            lda #>sync_irq2
            sta $ffff
            inc $d012
            lda #1
            sta $d019
            tsx
            cli
            .rept 32            ; the next IRQ hits one of these 2 cycle
            nop                 ; instructions: 0-1 cycles of jitter left
            .endrept
sync_irq2
            txs                 ; drop this IRQ's stack frame
            ldx #8              ; wait until the end of the line ...
-           dex
            bne -
            bit $00
            lda $d012           ; ... and remove the last cycle of jitter:
            cmp $d012           ; still the same line one cycle later?
            beq sync_point
sync_point
            lda #62             ; stable: start the timer, one line period
            sta $dc04
            lda #0
            sta $dc05
            lda #%00010001      ; force load, start, continuous
            sta $dc0e
            lda #1
            sta synced
            sta $d019
            rti

.if SYNC_TEST != 0
delay_a_small                   ; waits A (0-7) extra cycles, for the test
            and #7
            tax
-           dex
            bpl -
            rts
.endif

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
            lda #REFL_CRAM | 8  ; the reflection's own colour (%11 pixels)
            sta $d800 + REFL_ROW * 40,x
            lda #REFL_BLANK
            sta SCR_A + REFL_ROW * 40,x
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
            ; sprite pointers: the VIPP sprites 1-7 use blocks r*8+s for logo
            ; row r on screen A/B/C, the '10' (sprite 0) block 0 on all three
            ldx #1
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
            lda #SPR_PTR0
            sta SCR_A + $3f8
            sta SCR_B + $3f8
            sta SCR_C + $3f8

            lda #COL_LIGHT      ; %01 pixels: highlights (and the 10's body)
            sta $d025
            lda #COL_OUTLINE    ; %11 pixels: outline + drop shadow
            sta $d026
            jsr pulse_ten       ; colour of the (hires) 10
            ldx #BAR_COLS
-           lda #COL_BAR        ; %10 pixels: body, per sprite column
            sta $d027,x
            dex
            bne -
            jsr shine_logo      ; letter columns
            lda #%11111110      ; VIPP multicolor, the 10 hires
            sta $d01c
            lda #%00000001      ; the 10 is stretched vertically (24 x 42)
            sta $d017
            lda #0
            sta $d01d
            sta $d01b           ; sprites in front of text
            jsr position_logo
            jsr build_events
            lda #$ff
            sta $d015
            rts

; Advance the motion of both logos and set the X/Y registers: sprite 0 for
; the '10', sprites 1-7 for row 1 of the VIPP logo. Also computes the raster
; lines the FLD loop acts on for VIPP rows 2 and 3.
next_position
            lda atk_state       ; everything freezes during the attack
            bne position_logo
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
            jsr move_ten
            ; fall through

position_logo
            ldx y_idx
            lda bounce_y,x
            sta cur_y
            lda #0
            sta shake_x
            ldx shake_left      ; logo shake after a hit
            beq +
            dec shake_left
            txa
            and #7
            tax
            lda shake_dy,x
            clc
            adc cur_y
            sta cur_y
            lda shake_dx,x
            sta shake_x
            jmp ++
+           lda atk_state       ; frozen VIPP trembles a little
            beq +
            lda shine_phase
            and #3
            tax
            lda tremble_dy,x
            clc
            adc cur_y
            sta cur_y
            lda tremble_dx,x
            sta shake_x
+           lda cur_y
            ; logo row events for the kernel (merged in build_events)
            clc
            adc #8
            sta s_line+0        ; y+8: row 1 has started, load row 2 Y
            adc #13
            sta s_line+1        ; y+21: last line of row 1 -> row 2 pointers
            sta s_val+0
            adc #9
            sta s_line+2        ; y+30: load row 3 Y
            adc #12
            sta s_line+3        ; y+42: last line of row 2 -> row 3 pointers
            sta s_val+2

            lda ten_x           ; the 10
            sta $d000
            lda ten_y
            sta $d001
            lda ten_x+1         ; its X bit 8 ends up in bit 0 after 7 rors
            lsr a
            lda #0
            ror a
            sta msb

            ldx x_idx
            lda bounce_x,x
            clc
            adc shake_x
            sta x_lo
            lda shake_x         ; sign extend the shake offset
            and #$80
            beq +
            lda #$ff
+           adc bounce_xhi,x
            sta x_hi
            ldy #2              ; sprites 1-7
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

; The 10 moves in a straight line and bounces off the screen edges. X in
; whole pixels (16 bit), Y in 8.8 fixed point.
move_ten
            lda ten_dx
            bmi _left
            inc ten_x
            bne +
            inc ten_x+1
+           lda ten_x           ; reached the right edge?
            cmp #<TEN_X_MAX
            lda ten_x+1
            sbc #>TEN_X_MAX
            bcc _y
            lda #$ff
            sta ten_dx
            bne _y              ; always
_left       lda ten_x
            bne +
            dec ten_x+1
+           dec ten_x
            lda ten_x           ; reached the left edge?
            cmp #<TEN_X_MIN + 1
            lda ten_x+1
            sbc #>TEN_X_MIN + 1
            bcs _y
            lda #1
            sta ten_dx
_y          lda ten_dy
            bmi _up
            lda ten_yf
            clc
            adc #TEN_YSPEED
            sta ten_yf
            lda ten_y
            adc #0
            sta ten_y
            cmp #TEN_Y_MAX
            bcc _done
            lda #$ff
            sta ten_dy
            rts
_up         lda ten_yf
            sec
            sbc #TEN_YSPEED
            sta ten_yf
            lda ten_y
            sbc #0
            sta ten_y
            cmp #TEN_Y_MIN + 1
            bcs _done
            lda #1
            sta ten_dy
_done       rts

; ---------------------------------------------------------------------------
; IRQ chain: kernel (line 72) -> bottom (line 242) -> kernel ...
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
            ; water ripple: the reflection lines 244-250 get their own fine
            ; scroll (+-1 px, from make_ripple), written at the start of each
            ; line, before its visible part. $d016 is no colour register, so
            ; no grey dots.
            ldy #0
            ldx #RIPPLE_LINE
-           cpx $d012
            bne -
            lda ripple_d016,y
            sta $d016
            inx
            iny
            cpy #7
            bne -
-           cpx $d012           ; line 251: below the display
            bne -
            lda #$d8            ; 40 columns, multicolor, no fine scroll
            sta $d016

            jsr SID_PLAY
            jsr sid_out         ; music (+ sound effect on voice 3) to the SID
            jsr update_effects
            lda bg_col          ; background (flash) for the top of the screen
            sta $d021
            jsr next_position
            jsr shine_logo
            jsr pulse_ten
            jsr place_gun       ; after the VIPP sprite 7 registers are set
            jsr build_events
            jsr update_scroller
            jsr make_ripple

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
;  * works through the event list (built by build_events, raster order, "at
;    or past" test, so a skipped line never loses an event). Event kinds:
;      EV_SWAP  switch screen ($d018), which swaps all 8 sprite pointers at
;               once. Must happen early in the line: after the last pointer
;               fetch of the row above (cycle ~10), before the first fetch of
;               the next row (cycle 58)
;      EV_BEAM  the laser beam on the next 2 lines, cut exactly at the 10
;               (beam_event)
;      EV_Y     move the VIPP sprites down to the next logo row
;      EV_GUN_OFF give sprite 7 back from the gun to the VIPP logo
;      EV_GUN_ON  lend sprite 7 to the gun below the VIPP logo
;    The line of the next event is patched into the compare (_cmp), so a
;    line without events costs ~28 cycles, well below the 44 the CPU gets
;    on a line with 8 sprites.
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
            lda ev_line
            sta _cmp+1
            ldx $d012
            jmp _fld
_wait
-           cpx $d012
            beq -
            ldx $d012
_cmp        cpx #$ff            ; operand: line of the next event
            bcc _fld
            lda ev_kind,y       ; EV_SWAP = 0: the fast path
            bne +
            lda ev_val,y
            sta $d018
            jmp _next
+           cmp #EV_BEAM
            bne +
            jsr beam_event
            jmp _next
+           cmp #EV_GUN_OFF
            bne +
            jsr gun_off
            jmp _next
+           cmp #EV_GUN_ON
            bne +
            jsr gun_on
            jmp _next
+           lda ev_val,y        ; EV_Y
            jsr set_sprite_y
_next       iny
            lda ev_line,y
            sta _cmp+1
            jmp _cmp            ; another event on this line?
_fld        lda fld_d011,x
            sta $d011
            cpx #FLD_END
            bcc _wait
            lda #$1b            ; YSCROLL 3: badline (scroller row) at 227
            sta $d011
            lda #D018_A
            sta $d018
            lda bg_col          ; background for the scroller: written at the
-           cpx $d012           ; start of the next line (left border), so the
            beq -               ; 8565 grey dot of the write is not seen
            sta $d021
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

; Merge the 4 logo row events (s_*) and the attack's events (x_*, already
; in raster order) into the kernel's event list. On equal lines the logo
; event goes first (pointer swaps are time critical). Ends with line $ff.
build_events
            ldx #0              ; s index
            ldy #0              ; x index
            lda #0
            sta ev_n
_merge      cpx #4
            bcs _take_x
            cpy x_count
            bcs _take_s
            lda x_line,y
            cmp s_line,x
            bcc _take_x         ; attack event strictly earlier
_take_s     cpx #4
            bcs _end
            stx tmp_i
            lda s_line,x
            pha
            lda s_val,x
            pha
            lda s_kind,x
            ldx ev_n
            sta ev_kind,x
            pla
            sta ev_val,x
            pla
            sta ev_line,x
            inc ev_n
            ldx tmp_i
            inx
            jmp _merge
_take_x     cpy x_count
            bcs _end
            stx tmp_i
            ldx ev_n
            lda x_line,y
            sta ev_line,x
            lda x_val,y
            sta ev_val,x
            lda x_kind,y
            sta ev_kind,x
            inc ev_n
            ldx tmp_i
            iny
            jmp _merge
_end        ldx ev_n
            lda #$ff
            sta ev_line,x
            rts

set_sprite_y                    ; VIPP sprites 1-7 only, the 10 keeps its Y
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
SROW3       = SCR_A + REFL_ROW * 40         ; reflection

; Glyph g: chars 4g..4g+3 (2x2), reflection chars REFL_BLANK + 2g, +1
; (gen_assets.py, glyph 0 = space).

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
            lda SROW3+1,x
            sta SROW3,x
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
            lda cur_char
            asl a
            clc
            adc #REFL_BLANK
            sta SROW3+39
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
            lda cur_char
            asl a
            clc
            adc #REFL_BLANK + 1
            sta SROW3+39
            lda #0
            sta half
            rts

; Ripple values for the next frame: line 244+i gets the scroller's fine
; scroll plus a small wave (-1/0/+1), kept inside 0..7. The wave moves on
; every second frame.
make_ripple
            inc ripple_tick
            lda ripple_tick
            lsr a
            sta tmp_lo
            ldy #0
-           tya
            clc
            adc tmp_lo
            and #7
            tax
            lda xscroll
            clc
            adc ripple_tab,x
            bpl +
            lda #0
+           cmp #8
            bcc +
            lda #7
+           ora #$10            ; multicolor, 38 columns
            sta ripple_d016,y
            iny
            cpy #7
            bne -
            rts

ripple_tab  .byte 0, 1, 1, 0, $ff, $ff, 0, 1

; A bright shine sweeping left to right over the letters, one colour per
; letter sprite column (each column is 24 pixels wide). Bars keep their colour.
shine_logo
            inc shine_phase
            lda shine_phase
            lsr a
            sta shine_tmp
            ldx #1 + BAR_COLS
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

; The 10 is white and pulses through red every 2.5 seconds.
pulse_ten
            lda atk_state       ; the attack sets the colours itself
            ora expl_state
            bne +
            inc ten_phase
            lda ten_phase
            lsr a
            and #63
            tax
            lda ten_pulse,x
            sta $d027
+           rts

; ---------------------------------------------------------------------------
; The attack: when the 10 bumps into the VIPP logo both freeze. The 10 moves
; just clear of the logo (above or below it), so that sprite 7 is free on its
; lines: there it becomes a laser gun that slides in from the far side and
; shoots the 10 three times. The 10 explodes, the gun leaves, all resumes.
update_effects
            lda $d01e           ; sprite collisions since the last read (clears)
            ldx atk_state
            bne _attack
            and #1              ; the 10 bumped into something?
            bne +
            lda #1
            sta atk_armed       ; a fresh contact may start an attack again
            jmp _cooling
+           ldx expl_cool       ; contact: only a fresh one after the cooldown
            bne _cooling
            ldx atk_armed
            beq _cooling
            jsr plan_attack
            jmp _explosion
_cooling    lda expl_cool
            beq _explosion
            dec expl_cool
            jmp _explosion

_attack     cpx #ATK_RECOIL
            bne _gun_in
            jsr recoil_ten      ; Z = 1 when the 10 is in place
            bne _explosion
            lda #ATK_GUN_IN
            sta atk_state
            jmp _explosion

_gun_in     cpx #ATK_GUN_IN
            bne _shoot
            jsr slide_gun_in    ; C = 1 when the gun is in place
            bcc _explosion
            lda #ATK_SHOOT
            sta atk_state
            lda #SHOTS
            sta shots_left
            lda #0
            sta shot_age
            jmp _explosion

_shoot      cpx #ATK_SHOOT
            bne _boom
            lda shot_age
            bne +
            lda #HIT_FRAMES     ; a shot hits the 10
            sta ten_hit
            lda #SFX_LASER
            jsr sfx_start
+           lda shots_left      ; the last shot blows it up
            cmp #1
            bne +
            lda shot_age
            cmp #2
            bne +
            lda #ATK_BOOM
            sta atk_state
            jsr start_explosion
            jmp _explosion
+           inc shot_age
            lda shot_age
            cmp #SHOT_LEN
            bcc _explosion
            lda #0
            sta shot_age
            dec shots_left
            jmp _explosion

_boom       jsr slide_gun_out   ; C = 1 when the gun is gone
            bcc _explosion
            lda expl_state
            bne _explosion
            jsr resume          ; explosion over and gun gone

_explosion  lda expl_state
            beq _colours
            dec expl_tick
            bne _colours
            lda #EXPL_SPEED
            sta expl_tick
            inc expl_frame
            lda expl_frame
            cmp #EXPL_FRAMES
            bcc +
            jsr end_explosion
            jmp _colours
+           jsr show_expl_frame

_colours    lda atk_state       ; the 10 during the attack: white, light red
            beq _bg             ; when hit
            lda expl_state
            bne _bg
            lda #1
            ldx ten_hit
            beq +
            dec ten_hit
            lda #10
+           sta $d027

_bg         ; background colour: flash after an explosion, else black. It is
            ; set in the border (bottom IRQ, end of the kernel).
            lda #0
            ldx flash_left
            beq +
            dec flash_left
            lda flash_tab-1,x
+           sta bg_col
            rts

; The bump: the 10 recoils back the way it came (both directions reversed,
; same angle: 4 px across for every 3 px up/down) until it is clear of the
; logo with room for the gun: above the logo needs ten_y <= vy - 39 (the
; 48x42 gun ends 3 lines above VIPP), below needs ten_y >= vy + 53 (the gun
; starts after VIPP's last row). Moving down into the logo means recoiling
; up (above), moving up means recoiling down (below). Only when the logo is
; too close to the top/bottom for that side, the other side is used.
plan_attack
            lda #ATK_RECOIL
            sta atk_state
            ldx y_idx
            lda bounce_y,x      ; VIPP's Y without the tremble
            sta atk_vy
            lda ten_dy
            bmi _pref_below     ; was moving up: recoil down
            lda atk_vy
            cmp #93             ; room above?
            bcs _above
            bcc _below
_pref_below lda atk_vy
            cmp #136            ; room below?
            bcs _above
_below      lda #1
            sta atk_side
            lda ten_y           ; recoil at least RECOIL_MIN lines ...
            clc
            adc #RECOIL_MIN
            sta tmp_lo
            lda atk_vy          ; ... and down to vy+53
            clc
            adc #53
            cmp tmp_lo
            bcs +
            lda tmp_lo
+           cmp #189            ; the gun must end before the bottom IRQ
            bcc +
            lda #188
+           sta atk_ty
            sec                 ; distance in lines
            sbc ten_y
            jmp _frames
_above      lda #0
            sta atk_side
            lda ten_y           ; recoil at least RECOIL_MIN lines ...
            sec
            sbc #RECOIL_MIN
            bcs +
            lda #0
+           sta tmp_lo
            lda atk_vy          ; ... and up to vy-39
            sec
            sbc #39
            cmp tmp_lo
            bcc +
            lda tmp_lo
+           cmp #53             ; the beam line ten_y+21 must be >= 74
            bcs +
            lda #53
+           sta atk_ty
            lda ten_y
            sec
            sbc atk_ty

_frames     ; frames = ceil(distance / 3); x moves 4 px per frame
            ldx #0
-           cmp #1
            bcc +
            inx
            sbc #3
            bcs -
+           txa                 ; x distance = frames * 4
            asl a
            sta tmp_lo
            lda #0
            rol a
            asl tmp_lo
            rol a
            sta tmp_hi
            lda ten_dx          ; target x = ten_x - dx * distance
            bmi _x_plus
            lda ten_x
            sec
            sbc tmp_lo
            sta atk_tx
            lda ten_x+1
            sbc tmp_hi
            sta atk_tx+1
            bcs _clamp          ; no borrow: not below 0
            lda #0
            sta atk_tx+1
            jmp _x_min
_x_plus     lda ten_x
            clc
            adc tmp_lo
            sta atk_tx
            lda ten_x+1
            adc tmp_hi
            sta atk_tx+1

_clamp      ; keep the 10 on screen and where the beam cut fits:
            ; gun right (10's centre left of 184): x >= TEN_X_RGUN
            ; gun left: x <= TEN_X_LGUN
            lda atk_tx+1
            bne _gun_left
            lda atk_tx
            cmp #184 - 12
            bcs _gun_left
            lda #1
            sta gun_dir
            lda atk_tx
            cmp #TEN_X_RGUN
            bcs +
_x_min      lda #TEN_X_RGUN
            sta atk_tx
            lda #0
            sta atk_tx+1
            lda #1
            sta gun_dir
+           lda #<GUN_R_OUT
            sta gun_x
            lda #>GUN_R_OUT
            sta gun_x+1
            rts
_gun_left   lda #0
            sta gun_dir
            sta gun_x
            sta gun_x+1
            lda atk_tx          ; atk_tx > TEN_X_LGUN ?
            cmp #<TEN_X_LGUN + 1
            lda atk_tx+1
            sbc #>TEN_X_LGUN + 1
            bcc +
            lda #<TEN_X_LGUN
            sta atk_tx
            lda #>TEN_X_LGUN
            sta atk_tx+1
+           rts

; Recoil with ease-out: every frame the 10 covers 1/8 of the remaining
; distance (at least 1 px), in X and Y separately, so it kicks back fast and
; slows down smoothly on a straight line. Z = 1 when it is there.
recoil_ten
            lda #0
            sta moving
            sta ten_yf
            lda atk_ty          ; --- Y
            sec
            sbc ten_y
            beq _x
            inc moving
            bcc _up
            lsr a               ; down: step = d / 8, at least 1
            lsr a
            lsr a
            bne +
            lda #1
+           clc
            adc ten_y
            sta ten_y
            jmp _x
_up         eor #$ff            ; |d| = ten_y - atk_ty
            adc #1              ; C = 0 here
            lsr a
            lsr a
            lsr a
            bne +
            lda #1
+           sta tmp_lo
            lda ten_y
            sec
            sbc tmp_lo
            sta ten_y

_x          lda atk_tx          ; --- X (16 bit): d = atk_tx - ten_x
            sec
            sbc ten_x
            sta tmp_lo
            lda atk_tx+1
            sbc ten_x+1
            sta tmp_hi
            ora tmp_lo
            beq _done
            inc moving
            lda tmp_hi
            bmi _left
            jsr _step           ; right: ten_x += step
            clc
            adc ten_x
            sta ten_x
            bcc _done
            inc ten_x+1
            jmp _done
_left       lda #0              ; |d| = -d
            sec
            sbc tmp_lo
            sta tmp_lo
            lda #0
            sbc tmp_hi
            sta tmp_hi
            jsr _step           ; left: ten_x -= step
            sta tmp_lo
            lda ten_x
            sec
            sbc tmp_lo
            sta ten_x
            bcs _done
            dec ten_x+1
_done       lda moving
            rts

_step       lsr tmp_hi          ; A = |d| / 8, at least 1 (|d| < 2048)
            ror tmp_lo
            lsr tmp_hi
            ror tmp_lo
            lsr tmp_hi
            ror tmp_lo
            lda tmp_lo
            bne +
            lda #1
+           rts

; Gun slides in: left 1 px/frame to GUN_L_IN, right 2 px/frame to GUN_R_IN.
; C = 1 when it is in place.
slide_gun_in
            lda gun_dir
            bne +
            inc gun_x
            lda gun_x
            cmp #GUN_L_IN
            rts
+           lda gun_x
            sec
            sbc #2
            sta gun_x
            bcs +
            dec gun_x+1
+           lda gun_x           ; C = 1 when gun_x <= GUN_R_IN
            cmp #<GUN_R_IN + 1
            lda gun_x+1
            sbc #>GUN_R_IN + 1
            bcc +
            clc
            rts
+           sec
            rts

; Gun slides out again, 2 px/frame. C = 1 when it is gone.
slide_gun_out
            lda gun_dir
            bne _right
            lda gun_x
            beq _gone
            dec gun_x
            beq _gone
            dec gun_x
            beq _gone
            clc
            rts
_right      lda gun_x
            clc
            adc #2
            sta gun_x
            bcc +
            inc gun_x+1
+           lda gun_x           ; gone when gun_x >= GUN_R_OUT
            cmp #<GUN_R_OUT
            lda gun_x+1
            sbc #>GUN_R_OUT
            rts
_gone       sec
            rts

; Back to normal: the 10 moves away from the logo, no new bump for a while.
resume
            lda #ATK_IDLE
            sta atk_state
            sta atk_armed       ; needs a separation before the next attack
            lda atk_side        ; away from the logo: above: up, below: down
            beq +
            lda #1
            bne ++
+           lda #$ff
+           sta ten_dy
            lda ten_dx          ; and back the way it came across
            eor #$fe            ; +1 <-> -1
            sta ten_dx
            ; VIPP continues its bounce away from the 10: the bounce table is
            ; symmetric, so index Y_LEN - i has the same height as i but the
            ; opposite direction (first half: going up, second half: down)
            ldx y_idx
            beq ++              ; on the floor: it can only go up
            lda atk_side
            bne +
            cpx #Y_LEN / 2      ; 10 above: VIPP must go down (second half)
            bcs ++
            bcc _mirror
+           cpx #Y_LEN / 2 + 1  ; 10 below: VIPP must go up (first half)
            bcc +
_mirror     lda #Y_LEN
            sec
            sbc y_idx
            sta y_idx
+
            lda #COOL_FRAMES
            sta expl_cool
            rts

; During the attack sprite 7 is the gun on the lines next to the 10:
;  * gun above VIPP: set here (top of the frame), the kernel gives sprite 7
;    back to VIPP below the gun (EV_GUN_OFF)
;  * gun below VIPP: the kernel lends sprite 7 to the gun after VIPP's last
;    row (EV_GUN_ON, pointer in screen C); undone here at the next frame
; Also prepares the beam (EV_BEAM) while shooting.
place_gun
            lda #0
            sta x_count
            lda #SPR_PTR0 + 16 + 7      ; undo a gun below VIPP (last frame)
            sta SCR_C + $3ff
            lda $d017
            and #%01111111
            sta $d017
            lda $d01d
            and #%01111111
            sta $d01d
            lda atk_state
            cmp #ATK_GUN_IN
            bcs +
            rts
+           lda gun_dir         ; fully out of sight?
            bne +
            lda gun_x
            bne _vis
            rts
+           lda gun_x           ; right: gone at GUN_R_OUT
            cmp #<GUN_R_OUT
            lda gun_x+1
            sbc #>GUN_R_OUT
            bcc _vis
            rts
_vis        lda gun_dir         ; frame: GUN_PTR + dir*4 + side*2 + firing
            asl a
            asl a
            sta tmp_lo
            lda atk_side
            asl a
            ora tmp_lo
            ldx atk_state
            cpx #ATK_SHOOT
            bne +
            ldx shot_age
            cpx #3
            bcs +
            ora #1
+           clc
            adc #GUN_PTR
            sta gun_frame
            lda atk_side
            bne _g_below

            lda atk_ty          ; gun above VIPP
            clc
            adc #<GUN_ABOVE_Y
            sta gun_y
            lda $d00e           ; remember VIPP's sprite 7 for gun_off
            sta v7_x
            lda $d010
            sta v7_msb
            lda $d02e
            sta v7_col
            jsr gun_regs
            lda gun_frame
            sta SCR_A + $3ff
            ldx #0
            jsr beam_ev
            lda gun_y           ; sprite 7 back to VIPP below the gun
            clc
            adc #43
            sta x_line,x
            lda #EV_GUN_OFF
            sta x_kind,x
            inx
            stx x_count
            rts

_g_below    lda atk_ty          ; gun below VIPP
            clc
            adc #GUN_BELOW_Y
            sta gun_y
            ldx #0
            lda cur_y           ; after VIPP's last row
            clc
            adc #65
            sta x_line
            lda #EV_GUN_ON
            sta x_kind
            inx
            jsr beam_ev
            stx x_count
            rts

; add the beam event at x_*,X if a shot is visible; X = next free slot
beam_ev     lda atk_state
            cmp #ATK_SHOOT
            bne +
            ldy shot_age
            lda shot_tab,y
            beq +
            jsr beam_setup
            lda atk_ty
            clc
            adc #TEN_BEAM - 1
            sta x_line,x
            lda #EV_BEAM
            sta x_kind,x
            inx
+           rts

; sprite 7 registers for the gun (shared by place_gun and gun_on). Keeps X/Y.
gun_regs    lda gun_x
            sta $d00e
            lda gun_x+1
            lsr a
            lda $d010
            and #%01111111
            bcc +
            ora #%10000000
+           sta $d010
            lda gun_y
            sta $d00f
            lda #GUN_COL
            sta $d02e
            lda $d017
            ora #%10000000
            sta $d017
            lda $d01d
            ora #%10000000
            sta $d01d
            rts

; kernel event: sprite 7 becomes VIPP's again (row 1 of the logo)
gun_off
            lda v7_x
            sta $d00e
            lda v7_msb
            sta $d010
            lda cur_y
            sta $d00f
            lda v7_col
            sta $d02e
            lda $d017
            and #%01111111
            sta $d017
            lda $d01d
            and #%01111111
            sta $d01d
            lda #SPR_PTR0 + 7
            sta SCR_A + $3ff
            rts

; kernel event: sprite 7 becomes the gun below the VIPP logo (screen C)
gun_on
            jsr gun_regs
            lda gun_frame
            sta SCR_C + $3ff
            rts

; Patch beam_event for this frame. A = beam colour.
;  gun left : line b  [col from the start .. black from the cut]
;             line b+1 the same
;  gun right: line b  [black .. col from the cut], line b+1 the same, and
;             black again at the start of line b+2
; Wc = cut cycle. Writes: w0 at cycle 12 of line b (synced to the CIA timer),
; then w1 at Wc, w2 at 12 (next line), w3 at Wc, w4 at 12 (next line).
; Steps of (Wc - 12) use k = KA - Wc, steps of (75 - Wc) use k = KB + Wc.
; A write to $d02f (no register) is a dummy step.
beam_setup
            sta tmp_col
            txa
            pha
            ldy gun_dir         ; cut x = ten_x + CUT_LEFT / CUT_RIGHT
            lda ten_x
            clc
            adc cut_ofs,y
            sta tmp_lo
            lda ten_x+1
            adc #0
            lsr a               ; Wc = (x >> 3) + XC
            lda tmp_lo
            ror a
            lsr a
            lsr a
            clc
            adc #BEAM_XC
            cmp #BEAM_WMIN
            bcs +
            lda #BEAM_WMIN
+           cmp #BEAM_WMAX + 1
            bcc +
            lda #BEAM_WMAX
+           sta beam_wc
            lda #BEAM_KA        ; k for (Wc - 12) steps
            sec
            sbc beam_wc
            sta bj1+1
            sta bj3+1
            lda #BEAM_KB        ; k for (75 - Wc) steps
            clc
            adc beam_wc
            sta bj2+1
            sta bj4+1
            lda #BEAM_K0
            sta bk0+1
            lda gun_dir
            bne _right
            lda #$21            ; gun left: col, 0, col, 0, dummy
            sta bw0+1
            sta bw1+1
            sta bw2+1
            sta bw3+1
            lda #$2f
            sta bw4+1
            lda tmp_col
            sta bv0+1
            sta bv2+1
            lda #0
            sta bv1+1
            sta bv3+1
            sta bv4+1
            jmp _done
_right      lda #$2f            ; gun right: dummy, col, 0, col, 0
            sta bw0+1
            lda #$21
            sta bw1+1
            sta bw2+1
            sta bw3+1
            sta bw4+1
            lda #0
            sta bv0+1
            sta bv2+1
            sta bv4+1
            lda tmp_col
            sta bv1+1
            sta bv3+1
_done       pla
            tax
            rts

cut_ofs     .byte CUT_LEFT, CUT_RIGHT


start_explosion
            lda #SFX_BOOM
            jsr sfx_start
            lda #1
            sta expl_state
            lda #0
            sta expl_frame
            lda #EXPL_SPEED
            sta expl_tick
            lda $d01c           ; the 10 becomes multicolor
            ora #%00000001
            sta $d01c
            lda #FLASH_LEN
            sta flash_left
            lda #SHAKE_LEN
            sta shake_left
            ; fall through

show_expl_frame
            ldx expl_frame
            txa
            clc
            adc #EXPL_PTR0
            sta SCR_A + $3f8
            sta SCR_B + $3f8
            sta SCR_C + $3f8
            lda fire_colours,x  ; hottest: shared with the VIPP highlights
            sta $d025
            lda fire_colours + EXPL_FRAMES,x    ; shared with the VIPP outline
            sta $d026
            lda fire_colours + 2 * EXPL_FRAMES,x
            sta $d027
            rts

end_explosion
            lda #0
            sta expl_state
            lda #SPR_PTR0       ; the 10 re-forms
            sta SCR_A + $3f8
            sta SCR_B + $3f8
            sta SCR_C + $3f8
            lda $d01c
            and #%11111110
            sta $d01c
            lda #COL_LIGHT
            sta $d025
            lda #COL_OUTLINE
            sta $d026
            rts

; ---------------------------------------------------------------------------
; Sound: every SID write of the music player goes through a stub (music.inc)
; that writes it to the SID straight away, except voice 3 ($d40e-$d414) while
; a sound effect plays, and keeps a copy in SID_SHADOW. sid_out runs after
; the player: it writes the effect's next table row to voice 3, and when the
; effect is over it gives voice 3 back to the music (its last values).
SFX_LASER   = 0
SFX_BOOM    = 1

sid_out
.if MUSIC_DIRECT != 0
            rts
.else
            lda sfx_len
            beq _done
            ldy sfx_pos
            lda #0
            sta $d40e
            lda sfx_hi,y
            sta $d40f
            lda sfx_pw
            sta $d410
            lda sfx_pw+1
            sta $d411
            lda sfx_ad
            sta $d413
            lda sfx_sr
            sta $d414
            lda sfx_ctrl,y      ; control (gate) last
            sta $d412
            inc sfx_pos
            dec sfx_len
            bne _done
            ldx #14             ; effect over: voice 3 back to the music
-           lda SID_SHADOW,x
            sta $d400,x
            inx
            cpx #21
            bne -
_done       rts
.endif

; start effect A, unless the explosion is still playing (it has priority)
sfx_start
.if SFX_OFF != 0
            rts
.endif
            tax
            lda sfx_len
            beq +
            lda sfx_cur
            cmp #SFX_BOOM
            bne +
            cpx #SFX_BOOM
            bne _busy
+           stx sfx_cur
            lda sfx_first,x
            sta sfx_pos
            lda sfx_length,x
            sta sfx_len
            lda sfx_pwlo,x
            sta sfx_pw
            lda sfx_pwhi,x
            sta sfx_pw+1
            lda sfx_adv,x
            sta sfx_ad
            lda sfx_srv,x
            sta sfx_sr
_busy       rts

; per effect: first table row, rows, pulse width, attack/decay, sustain/release
sfx_first   .byte 0, LASER_ROWS
sfx_length  .byte LASER_ROWS, BOOM_ROWS
sfx_pwlo    .byte $00, $00
sfx_pwhi    .byte $08, $08
sfx_adv     .byte $00, $00
sfx_srv     .byte $f3, $f9
; rows: the first row sets the test bit (gate off, oscillator reset) so the
; envelope restarts cleanly whatever the drums were doing
; laser "pew": pulse wave, fast falling pitch
sfx_hi      .byte $00, $60, $54, $48, $3e, $34, $2c, $24, $1e, $18, $14
LASER_ROWS  = * - sfx_hi
; explosion: noise, pitch rumbles down while the sound dies out
            .byte $00, $38, $30, $2a, $25, $21, $1e, $1b, $18, $16, $14, $12
            .byte $11, $10, $0f, $0e, $0d, $0c, $0b, $0b, $0a, $0a, $09, $09
            .byte $08, $08, $07, $07, $07, $06, $06, $06, $05, $05, $05, $05
            .byte $04, $04, $04, $04, $03, $03, $03, $03, $03, $03
BOOM_ROWS   = * - sfx_hi - LASER_ROWS
sfx_ctrl    .byte $08
            .fill LASER_ROWS - 3, $41           ; pulse + gate
            .byte $40, $40                      ; gate off: release
            .byte $08
            .fill 8, $81                        ; noise + gate
            .fill BOOM_ROWS - 9, $80            ; gate off: long release
            .cerror * - sfx_ctrl != LASER_ROWS + BOOM_ROWS, "sfx tables differ in length"

flash_tab   .byte 11, 12, 15, 15, 1, 1           ; read backwards: white > grey
shot_tab    .byte 1, 1, 10, 10, 2, 2             ; beam: white > light red > red
            .fill SHOT_LEN - 6, 0                ; pause between shots
shake_dx    .byte 0, 2, $fe, 1, $ff, 2, $fe, 1
shake_dy    .byte 1, $ff, 2, $fe, 1, 0, $ff, 2
tremble_dx  .byte 0, 1, 0, $ff
tremble_dy  .byte 1, 0, $ff, 0
fire_colours .binary "../build/fire_colours.bin"

ten_pulse   .fill 48, 1
            .byte 15, 10, 10, 2, 2, 2, 2, 2, 2, 2, 10, 10, 15, 1, 1, 1

shine       .fill 51, COL_LETTER           ; 64 entries: letter colour with a
            .byte $03,$03,$0d,$01,$01,$01,$0d,$03,$03 ; cyan/white glint
            .fill 4, COL_LETTER

; --- variables -----------------------------------------------------------------
synced      .byte 0
x_phase     .byte 0
x_idx       .byte 0
y_idx       .byte 0
cur_y       .byte 0
ev_line     .fill 8, $ff        ; kernel events (see irq_kernel), $ff = end
ev_kind     .fill 8, 0
ev_val      .fill 8, 0
ev_n        .byte 0
s_line      .byte 0, 0, 0, 0    ; logo row events
s_kind      .byte EV_Y, EV_SWAP, EV_Y, EV_SWAP
s_val       .byte 0, D018_B, 0, D018_C
x_line      .byte 0, 0, 0       ; attack events (gun on/off, beam)
x_kind      .byte 0, 0, 0
x_val       .byte 0, 0, 0
x_count     .byte 0
tmp_i       .byte 0
x_lo        .byte 0
x_hi        .byte 0
msb         .byte 0
xscroll     .byte 7
half        .byte 0
cur_char    .byte 0
ripple_tick .byte 0
ripple_d016 .fill 7, $10
shine_phase .byte 0
shine_tmp   .byte 0
ten_x       .word 100
ten_y       .byte 60
ten_yf      .byte 0
ten_dx      .byte 1             ; +1 / -1 ($ff)
ten_dy      .byte 1
ten_phase   .byte 0
expl_state  .byte 0             ; 0 = normal, 1 = exploding
expl_frame  .byte 0
expl_tick   .byte 0
expl_cool   .byte 0
flash_left  .byte 0
shake_left  .byte 0
shake_x     .byte 0
bg_col      .byte 0
atk_state   .byte ATK_IDLE
shots_left  .byte 0
shot_age    .byte 0
ten_hit     .byte 0
gun_x       .word 0
gun_y       .byte 0
gun_dir     .byte 0             ; 0 = gun at the left edge, 1 = at the right
gun_frame   .byte 0
atk_side    .byte 0             ; 0 = the 10 above VIPP, 1 = below
atk_armed   .byte 1             ; 0 until the 10 and VIPP have separated
sid_val     .byte 0
sfx_cur     .byte 0
sfx_pos     .byte 0
sfx_len     .byte 0             ; rows left, 0 = voice 3 belongs to the music
sfx_pw      .word 0
sfx_ad      .byte 0
sfx_sr      .byte 0
atk_vy      .byte 0
atk_ty      .byte 0
atk_tx      .word 0
moving      .byte 0
tmp_lo      .byte 0
tmp_hi      .byte 0
tmp_col     .byte 0
beam_wc     .byte 0
beam_ysave  .byte 0
v7_x        .byte 0
v7_msb      .byte 0
v7_col      .byte 0

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
            .cerror * > EXPLOSION, "sprites overlap the explosion frames"

            * = EXPLOSION
            .binary "../build/explosion.bin"
            .cerror * != GUN, "explosion frames do not end at the gun"
            .binary "../build/gun.bin"
            .cerror * > IDLE_BYTE, "gun frames overlap the VIC idle byte"

.if MUSIC_DIRECT != 0
            * = SID_LOAD
            .binary "../assets/Commando.sid", $7e   ; original player
            .cerror * != $5fc7, "unexpected Commando.sid size"
.else
            .include "../build/music.inc"           ; player with SID stubs
.endif

; ---------------------------------------------------------------------------
; EV_BEAM (kernel, on line b-1): draws the beam on lines b and b+1 with
; cycle exact colour writes (operands patched by beam_setup). The CIA timer
; (sync_timer) gives the exact cycle once; a "sled" of cmp #$c9 bytes with a
; final cmp $ea then waits 4..65 cycles with single cycle resolution,
; depending on where it is entered: entry k waits 65 - k cycles.
            * = $6000           ; free RAM after the music
beam_event
            sty beam_ysave
bk0         lda #0              ; operand: BEAM_K0
            sec
            sbc $dc04           ; exact cycle from the timer
            sta bj0+1
bv0         ldy #0
bj0         jmp sled0
            .align 256
sled0       .fill 62, $c9
            .byte $c5, $ea
bw0         sty $d021           ; w0: cycle 12 of line b
bv1         ldy #0
bj1         jmp sled1
            .align 256
sled1       .fill 62, $c9
            .byte $c5, $ea
bw1         sty $d021           ; w1: cut cycle of line b
bv2         ldy #0
bj2         jmp sled2
            .align 256
sled2       .fill 62, $c9
            .byte $c5, $ea
bw2         sty $d021           ; w2: cycle 12 of line b+1
bv3         ldy #0
bj3         jmp sled3
            .align 256
sled3       .fill 62, $c9
            .byte $c5, $ea
bw3         sty $d021           ; w3: cut cycle of line b+1
bv4         ldy #0
bj4         jmp sled4
            .align 256
sled4       .fill 62, $c9
            .byte $c5, $ea
bw4         sty $d021           ; w4: cycle 12 of line b+2
            ldy beam_ysave
            ldx $d012           ; the kernel continues on the current line
            rts
