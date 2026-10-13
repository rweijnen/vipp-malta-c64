; ---------------------------------------------------------------------------
; VIPP Mission: an Impossible Mission (Epyx, 1984) mode, started with Space.
;
; Graphics, sounds and speech come from assets/im/ (extracted from the
; user's own copy of the game with tools/im/extract.py, private event use
; only, never in git).
;
; Stage 0: skeleton. Shows an original room with the agent standing in it,
; Space returns to the demo.
;
; Memory (VIC bank 2, $8000-$bfff; the VIC sees char ROM at $9000-$9fff,
; so only CPU data goes there):
;   $8000-$83ff  mission screen
;   $8800-$8fff  room charset
;   $9000-$9fff  room data (CPU only)
;   $a800-$b7ff  agent sprites (64 blocks)
; Code: $7000-$7fff (and $c000-$cfff later).
; ---------------------------------------------------------------------------

            .include "../assets/im/room_test.inc"

M_SCREEN    = $8000
M_CHARSET   = $8800
M_AGENT     = $a800
M_D018      = ((M_SCREEN & $3fff) / $400) << 4 | ((M_CHARSET & $3fff) / $800) << 1
AGENT_PTR0  = (M_AGENT & $3fff) / 64
MISSION_IRQ_LINE = 250

; agent frame 14 (standing): body = block $1c, legs $1d, white overlay $1e
AGENT_STAND = $1c
AGENT_X     = 200
AGENT_Y     = 168               ; sprite Y of the body piece

            * = $7000
mission_run
            sei
            lda #0
            sta $d01a
            sta $d015
            lda #$ff
            sta $d019
            lda #0              ; silence the music
            sta $d418
            sta $d404
            sta $d40b
            sta $d412

            lda $dd00           ; VIC bank 2
            and #%11111100
            ora #%00000001
            sta $dd00

            ldx #0              ; room screen + colour RAM (1000 bytes each)
-           lda room_test_screen,x
            sta M_SCREEN,x
            lda room_test_screen + 250,x
            sta M_SCREEN + 250,x
            lda room_test_screen + 500,x
            sta M_SCREEN + 500,x
            lda room_test_screen + 750,x
            sta M_SCREEN + 750,x
            lda room_test_colram,x
            sta $d800,x
            lda room_test_colram + 250,x
            sta $d800 + 250,x
            lda room_test_colram + 500,x
            sta $d800 + 500,x
            lda room_test_colram + 750,x
            sta $d800 + 750,x
            inx
            cpx #250
            bne -

            lda #0
            sta $d020
            lda #ROOM_TEST_BG
            sta $d021
            lda #ROOM_TEST_MC1
            sta $d022
            lda #ROOM_TEST_MC2
            sta $d023
            lda #$1b
            sta $d011
            lda #$d8            ; multicolor text, 40 columns
            sta $d016
            lda #M_D018
            sta $d018

            ; the agent: 3 hires sprites (1 white overlay, 2 body, 3 legs)
            lda #AGENT_PTR0 + AGENT_STAND
            sta M_SCREEN + $3fa
            lda #AGENT_PTR0 + AGENT_STAND + 1
            sta M_SCREEN + $3fb
            lda #AGENT_PTR0 + AGENT_STAND + 2
            sta M_SCREEN + $3f9
            lda #AGENT_X
            sta $d002
            sta $d004
            sta $d006
            lda #0
            sta $d010
            sta $d01c
            sta $d017
            sta $d01d
            sta $d01b
            lda #AGENT_Y + 12
            sta $d003
            lda #AGENT_Y
            sta $d005
            lda #AGENT_Y + 21
            sta $d007
            lda #1
            sta $d028
            lda #11
            sta $d029
            sta $d02a
            lda #%00001110
            sta $d015

            lda #<mission_irq
            sta $fffe
            lda #>mission_irq
            sta $ffff
            lda #MISSION_IRQ_LINE
            sta $d012
            lda #1
            sta $d01a
            lda #$ff
            sta $d019
            cli

-           lda want_mode       ; Space again: back to the demo
            beq -
            lda #0
            sta want_mode
            sei
            lda #0
            sta $d01a
            sta $d015
            lda #$ff
            sta $d019
            rts

mission_irq
            pha
            txa
            pha
            tya
            pha
            jsr check_space
            lda #$ff
            sta $d019
            pla
            tay
            pla
            tax
            pla
            rti
mission_code_end
            .cerror mission_code_end > $8000, "mission code beyond $7fff"

; --- mission data in bank 2 --------------------------------------------------------
            * = M_CHARSET
            .binary "../assets/im/charset_rooms.bin"
            .cerror * != $9000, "room charset must end at $9000 (char ROM area follows)"

            * = $9000           ; CPU-only area (the VIC sees char ROM here)
room_test_screen
            .binary "../assets/im/room_test_screen.bin"
room_test_colram
            .binary "../assets/im/room_test_colram.bin"
            .cerror * > $a000, "room data beyond $9fff"

            * = M_AGENT
            .binary "../assets/im/agent_sprites.bin"
            .cerror * != $b800, "agent sprites must be 64 blocks"
