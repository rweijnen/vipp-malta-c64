; ---------------------------------------------------------------------------
; VIPP Mission: an Impossible Mission (Epyx, 1984) mode, started with Space.
;
; Graphics, sounds and speech come from assets/im/ (extracted from the
; user's own copy of the game with tools/im/extract.py, private event use
; only, never in git); tools/im/gen_mission.py turns them into tables.
;
; Stage 1: the agent runs, somersaults and stands in an original room,
; driven by a script, with the original footsteps. Space returns to the demo.
;
; Like the original, the game logic steps once every 3 frames (a "tick"):
; the agent moves 5 px and one animation frame per tick.
;
; Memory (VIC bank 2, $8000-$bfff; the VIC sees char ROM at $9000-$9fff,
; so only CPU data goes there):
;   $8000-$83ff  mission screen
;   $8800-$8fff  room charset
;   $9000-$9fff  room data (CPU only)
;   $a800-$b7ff  agent sprites (64 blocks)
; Code: $7000-$7fff (and $c000-$cfff later).
; Zero page $10-$2f is the mission's (the demo keeps nothing there, and its
; music player is re-initialised when the demo comes back).
; ---------------------------------------------------------------------------

            .include "../assets/im/room_test.inc"
            .include "../build/mission_agent.inc"

M_SCREEN    = $8000
M_CHARSET   = $8800
M_AGENT     = $a800
M_D018      = ((M_SCREEN & $3fff) / $400) << 4 | ((M_CHARSET & $3fff) / $800) << 1
AGENT_PTR0  = (M_AGENT & $3fff) / 64
MISSION_IRQ_LINE = 250
TICK_FRAMES = 3                 ; the original steps its game every 3 frames
RUN_PX      = 5                 ; px per tick while running

FACE_RIGHT  = $01               ; the original's facing values ($50)
FACE_LEFT   = $80
FR_STAND    = 14                ; animation frames
FR_RUN_TOP  = 13                ; run cycle 13 -> 0
FR_FLIP_TOP = 27                ; somersault 27 -> 16
FR_FLIP_END = 16

; agent body sprite Y for standing on the platform in character row r
floor_y     .function r
            .endf 8 * r + 10

; zero page
m_p         = $10               ; 2: sprite block being mirrored
m_t         = $12
ag_x        = $13               ; 2: agent origin X (sprite coordinates)
ag_y        = $15               ; agent origin Y (body sprite)
ag_frame    = $16
ag_face     = $17
sc_p        = $18               ; 2: script pointer
sc_wait     = $1a
sc_cmd      = $1b               ; command in progress
tick_ctr    = $1c
en_bits     = $1d
hi_bits     = $1e
pc_blk      = $1f
pc_y        = $20               ; 3: per piece Y
pc_xl       = $23               ; 3: per piece X low
pc_xh       = $26               ; 3: per piece X high
d_lo        = $29
d_hi        = $2a

; script commands
C_STAND     = 0                 ; ticks
C_FACE      = 1                 ; FACE_RIGHT / FACE_LEFT
C_RUN       = 2                 ; target X (word): run in the facing direction until there
C_FLIP      = 3                 ; somersault in the facing direction
C_GOTO      = 4                 ; address (word)

            * = $7000
mission_run
            sei
            lda #0
            sta $d01a
            sta $d015
            lda #$ff
            sta $d019
            ldx #$18            ; silence the music: all SID registers 0
            lda #0
-           sta $d400,x
            dex
            bpl -

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
            lda #0
            sta $d010
            sta $d01c
            sta $d017
            sta $d01d
            sta $d01b
            lda #1
            sta $d028
            lda #11
            sta $d029
            sta $d02a

            lda #<test_script
            sta sc_p
            lda #>test_script
            sta sc_p + 1
            lda #<150
            sta ag_x
            lda #>150
            sta ag_x + 1
            lda #floor_y(24)
            sta ag_y
            lda #FACE_RIGHT
            sta ag_face
            jsr script_next     ; start the first command
            jsr agent_draw
            lda #TICK_FRAMES
            sta tick_ctr

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
            ldx #$18            ; mission sounds off
            lda #0
-           sta $d400,x
            dex
            bpl -
            rts

mission_irq
            pha
            txa
            pha
            tya
            pha
            jsr check_space
            dec tick_ctr
            bne +
            lda #TICK_FRAMES
            sta tick_ctr
            jsr script_tick
            jsr agent_draw
            jsr footsteps
+           lda #$ff
            sta $d019
            pla
            tay
            pla
            tax
            pla
            rti

; --- script -----------------------------------------------------------------------
; Fetch the next command and start it (in the same tick).
script_next
            ldy #0
            lda (sc_p),y
            sta sc_cmd
            cmp #C_STAND
            beq _stand
            cmp #C_FACE
            beq _face
            cmp #C_RUN
            beq _run
            cmp #C_FLIP
            beq _flip
            cmp #C_GOTO
            beq _goto
            ; unknown command: show it plainly (red border) and stop
            lda #2
            sta $d020
            jmp *
_stand      iny
            lda (sc_p),y
            sta sc_wait
            lda #FR_STAND
            sta ag_frame
            lda #2
            jmp advance
_face       iny
            lda (sc_p),y
            sta ag_face
            lda #2
            jsr advance
            jmp script_next
_run        lda #FR_RUN_TOP     ; starting to run moves at once, like the original
            sta ag_frame
            jmp run_step
_flip       lda #FR_FLIP_TOP
            sta ag_frame
            lda #1
            jmp advance
_goto       iny
            lda (sc_p),y
            tax
            iny
            lda (sc_p),y
            sta sc_p + 1
            stx sc_p
            jmp script_next

advance     clc                 ; sc_p += A
            adc sc_p
            sta sc_p
            bcc +
            inc sc_p + 1
+           rts

; One game tick of the command in progress.
script_tick
            lda sc_cmd
            cmp #C_RUN
            beq _run
            cmp #C_FLIP
            beq _flip
            ; C_STAND
            dec sc_wait
            bne +
            jmp script_next
+           rts
_run        ldx ag_frame        ; run cycle 13 -> 0, then 13 again
            dex
            bpl +
            ldx #FR_RUN_TOP
+           stx ag_frame
            jmp run_step
_flip       lda ag_frame
            cmp #FR_FLIP_END
            beq _landed
            dec ag_frame
            rts
_landed     lda #<AGENT_FLIP_DX ; the origin moves to where the agent landed
            ldx #>AGENT_FLIP_DX
            jsr move_x
            jmp script_next

; Move RUN_PX px in the facing direction; at or past the target X the
; next command starts.
run_step    lda #RUN_PX
            ldx #0
            jsr move_x
            ldy #1
            bit ag_face
            bmi _left
            lda ag_x            ; facing right: done when ag_x >= target
            cmp (sc_p),y
            iny
            lda ag_x + 1
            sbc (sc_p),y
            bcs _done
            rts
_left       lda (sc_p),y        ; facing left: done when target >= ag_x
            cmp ag_x
            iny
            lda (sc_p),y
            sbc ag_x + 1
            bcs _done
            rts
_done       lda #3
            jsr advance
            jmp script_next

; ag_x += A/X (a positive distance) in the facing direction
move_x      sta d_lo
            stx d_hi
            bit ag_face
            bmi _left
            clc
            lda ag_x
            adc d_lo
            sta ag_x
            lda ag_x + 1
            adc d_hi
            sta ag_x + 1
            rts
_left       sec
            lda ag_x
            sbc d_lo
            sta ag_x
            lda ag_x + 1
            sbc d_hi
            sta ag_x + 1
            rts

; --- drawing ------------------------------------------------------------------------
; The pieces of the current frame: block, mirrored to the facing if needed,
; sprite pointer, position. Sprite 1 = white overlay, 2 = body, 3 = legs.
agent_draw
            lda #0
            sta en_bits
            ldx #2
_piece      lda ag_frame
            clc
            adc piece_ofs,x
            tay
            lda ag_blk1,y
            cmp #$ff
            beq _next
            sta pc_blk
            clc
            adc #AGENT_PTR0
            sta M_SCREEN + $3f9,x
            lda en_bits
            ora spr_bit,x
            sta en_bits
            lda ag_dy1,y
            clc
            adc ag_y
            sta pc_y,x
            lda ag_dx1,y        ; signed offset, mirrored when facing left
            bit ag_face
            bpl +
            eor #$ff
            clc
            adc #1
+           sta d_lo
            lda #0
            bit d_lo
            bpl +
            lda #$ff
+           sta d_hi
            clc
            lda ag_x
            adc d_lo
            sta pc_xl,x
            lda ag_x + 1
            adc d_hi
            sta pc_xh,x
            txa
            pha
            lda pc_blk
            jsr mirror_block
            pla
            tax
_next       dex
            bpl _piece

            lda pc_y
            sta $d003
            lda pc_y + 1
            sta $d005
            lda pc_y + 2
            sta $d007
            lda pc_xl
            sta $d002
            lda pc_xl + 1
            sta $d004
            lda pc_xl + 2
            sta $d006
            lda #0
            sta hi_bits
            ldx #2
-           lda pc_xh,x
            and #1
            beq +
            lda hi_bits
            ora spr_bit,x
            sta hi_bits
+           dex
            bpl -
            lda $d010
            and #%11110001
            ora hi_bits
            sta $d010
            lda $d015
            and #%11110001
            ora en_bits
            sta $d015
            rts

piece_ofs   .byte 0, 84, 168    ; ag_blk2 = ag_blk1 + 84 etc. (28 frames x 3 tables)
spr_bit     .byte %0010, %0100, %1000
            .cerror ag_blk2 - ag_blk1 != 84 || ag_blk3 - ag_blk1 != 168, "agent table layout"

; Mirror sprite block A (0-63 of the agent) in place when its facing
; (byte 63, as in the original) differs from the agent's.
mirror_block
            ldx #0
            stx m_p
            lsr a               ; block * 64 = block << 6
            ror m_p
            lsr a
            ror m_p
            clc
            adc #>M_AGENT
            sta m_p + 1
            ldy #63
            lda (m_p),y
            cmp ag_face
            beq _done
            tax
            lda rev_bits,x      ; $80 <-> $01, the same as the facing values
            sta (m_p),y
            ldy #0
-           lda (m_p),y         ; one row: 3 bytes, reversed and swapped
            tax
            lda rev_bits,x
            sta m_t
            iny
            lda (m_p),y
            tax
            lda rev_bits,x
            sta (m_p),y
            iny
            lda (m_p),y
            tax
            lda rev_bits,x
            dey
            dey
            sta (m_p),y
            iny
            iny
            lda m_t
            sta (m_p),y
            iny
            cpy #63
            bne -
_done       rts

; --- sound ----------------------------------------------------------------------------
; Footsteps, as the original ($8e77): voice 3 noise when the feet touch the
; floor (frames 0, 7 and 16), gate off on frames 14, 10 and 3.
footsteps
            lda #5
            sta $d418
            lda ag_frame
            beq _step
            cmp #7
            beq _step
            cmp #16
            beq _step
            cmp #14
            beq _off
            cmp #10
            beq _off
            cmp #3
            beq _off
            rts
_off        lda #$80
            sta $d412
            rts
_step       ldx #$86            ; facing left: $861e
            ldy #$1e
            lda ag_face
            bmi +
            ldx #$c8            ; facing right: $c8f3
            ldy #$f3
+           stx $d40f
            sty $d40e
            lda #$05
            sta $d413
            lda #$39
            sta $d414
            lda #$81
            sta $d412
            rts

; --- the test walk (stage 1): the long floor at the bottom of the room -----------
test_script
            .byte C_FACE, FACE_RIGHT
            .byte C_STAND, 30
            .byte C_RUN
            .word 220
            .byte C_FLIP
            .byte C_RUN
            .word 300
            .byte C_STAND, 20
            .byte C_FACE, FACE_LEFT
            .byte C_STAND, 6
            .byte C_RUN
            .word 250
            .byte C_FLIP
            .byte C_RUN
            .word 150
            .byte C_STAND, 20
            .byte C_GOTO
            .word test_script

            .align 256
rev_bits                        ; bit-reversed bytes, for mirroring hires sprites
            .for i := 0, i < 256, i += 1
            .byte ((i >> 7) & 1) | ((i >> 5) & 2) | ((i >> 3) & 4) | ((i >> 1) & 8) | ((i << 1) & 16) | ((i << 3) & 32) | ((i << 5) & 64) | ((i << 7) & 128)
            .next

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
