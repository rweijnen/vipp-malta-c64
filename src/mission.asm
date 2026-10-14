; ---------------------------------------------------------------------------
; VIPP Mission: an Impossible Mission (Epyx, 1984) mode, started with Space.
;
; Graphics, sounds and speech come from assets/im/ (extracted from the
; user's own copy of the game with tools/im/extract.py and extract_lift.py,
; private event use only, never in git); tools/im/gen_mission.py turns them
; into tables.
;
; Stage 2: the lift. The agent rides down the shaft (scrolling like the
; original: one character row every 2 frames, the view redrawn in two
; halves), walks out through a corridor into a room and back, with the
; original lift hum and footsteps. Space returns to the demo.
;
; Like the original, the game logic steps once every 3 frames (a "tick"):
; the agent moves 5 px and one animation frame per tick.
;
; Memory (VIC bank 2, $8000-$bfff; the VIC sees char ROM at $9000-$9fff,
; so only CPU data goes there):
;   $8000-$83ff  mission screen
;   $8400-$84bf  lift sprites (side lines, car hanger, panel marker)
;   $8800-$8fff  room charset
;   $9000-$9fff  room and lift data (CPU only)
;   $a000-$a7ff  lift charset
;   $a800-$b7ff  agent sprites (64 blocks)
;   $b800-$bfff  pocket computer panel charset
; Code: $7000-$7fff (and $c000-$cfff later).
; Zero page $10-$3f is the mission's (the demo keeps nothing there, and its
; music player is re-initialised when the demo comes back).
; ---------------------------------------------------------------------------

            .include "../assets/im/room_test.inc"
            .include "../assets/im/lift.inc"
            .include "../build/mission_agent.inc"

M_SCREEN    = $8000
M_LIFTSPR   = $8400
M_CHARSET   = $8800
M_LIFTCHR   = $a000
M_AGENT     = $a800
M_PANELCHR  = $b800
D018_ROOM   = ((M_SCREEN & $3fff) / $400) << 4 | ((M_CHARSET & $3fff) / $800) << 1
D018_LIFT   = ((M_SCREEN & $3fff) / $400) << 4 | ((M_LIFTCHR & $3fff) / $800) << 1
D018_PANEL  = ((M_SCREEN & $3fff) / $400) << 4 | ((M_PANELCHR & $3fff) / $800) << 1
AGENT_PTR0  = (M_AGENT & $3fff) / 64
LIFTSPR_PTR = (M_LIFTSPR & $3fff) / 64
MAIN_LINE   = 252               ; the mission's frame IRQ, in the bottom border
SPLIT_LINE  = 169               ; lift scene: panel colours on line 170/171
TICK_FRAMES = 3                 ; the original steps its game every 3 frames
RUN_PX      = 5                 ; px per tick while running

FACE_RIGHT  = $01               ; the original's facing values ($50)
FACE_LEFT   = $80
FR_STAND    = 14                ; animation frames
FR_RUN_TOP  = 13                ; run cycle 13 -> 0
FR_FLIP_TOP = 27                ; somersault 27 -> 16
FR_FLIP_END = 16

SC_ROOM     = 0                 ; scenes
SC_LIFT     = 1

; lift scene layout (as in the original)
VIEW_ROWS   = 15                ; shaft view rows 0-14, panel rows 15-24
CAR_ROW     = 4                 ; the car (and a corridor in line with it) starts here
LIFT_AGENT_X = 172
LIFT_AGENT_Y = 94
CORR_L      = 1                 ; corridor sides
CORR_R      = 2

; agent body sprite Y for standing on the platform in character row r
floor_y     .function row
            .endf 8 * row + 10

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
scene       = $2b
sh_pos      = $2c               ; shaft row shown in view row 0
sh_target   = $2d               ; ride until sh_pos gets here
sh_phase    = $2e               ; 0 stopped, 1 next frame: top half, 2: bottom half, 3 hum spins down
snd_v1      = $2f               ; lift hum pitch ramps (the original's $25/$26)
snd_v2      = $30
lfsr3       = $31               ; the original's $e1: 3 bit noise 5,6,7,3,1,4,2
gw          = $32               ; shaft row being generated
gt          = $33
src_s       = $34               ; 2: row copy pointers: screen
dst_s       = $36               ; 2
src_c       = $38               ; 2: colour RAM
dst_c       = $3a               ; 2
rnd         = $3c
fill_c      = $3d
gk          = $3e
snd_hold    = $3f

; script commands
C_STAND     = 0                 ; ticks
C_FACE      = 1                 ; FACE_RIGHT / FACE_LEFT
C_RUN       = 2                 ; target X (word): run in the facing direction until there
C_FLIP      = 3                 ; somersault in the facing direction
C_GOTO      = 4                 ; address (word)
C_SCENE     = 5                 ; scene, shaft row ($ff: keep), X (word), Y, facing
C_RIDE      = 6                 ; shaft row: ride the lift until view row 0 shows it

            * = $7000
mission_run
            sei
            lda #0
            sta $d01a
            sta $d015
            lda #$ff
            sta $d019
            jsr sid_off

            lda $dd00           ; VIC bank 2
            and #%11111100
            ora #%00000001
            sta $dd00
            lda #0
            sta $d020
            sta sh_pos

            lda #<mission_script
            sta sc_p
            lda #>mission_script
            sta sc_p + 1
            jsr script_next     ; the first command sets up the first scene
            lda #TICK_FRAMES
            sta tick_ctr
            jsr next_irq
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
            sta $d017
            sta $d01c
            lda #$ff
            sta $d019
            jmp sid_off

sid_off     ldx #$18            ; all SID registers 0
            lda #0
-           sta $d400,x
            dex
            bpl -
            rts

; The next IRQ: in the lift scene the panel split comes first.
next_irq    lda scene
            cmp #SC_LIFT
            beq +
            lda #<irq_main
            sta $fffe
            lda #>irq_main
            sta $ffff
            lda #MAIN_LINE
            sta $d012
            rts
+           lda #<irq_split
            sta $fffe
            lda #>irq_split
            sta $ffff
            lda #SPLIT_LINE
            sta $d012
            rts

; --- frame IRQ (line 252, bottom border) ------------------------------------------
irq_main
            pha
            txa
            pha
            tya
            pha
            lda scene
            cmp #SC_LIFT
            bne +
            lda #LIFT_BG        ; the shaft view's colours for the next frame
            sta $d021
            lda #LIFT_MC1
            sta $d022
            lda #LIFT_MC2
            sta $d023
            lda #D018_LIFT
            sta $d018
            jsr lift_frame      ; scrolling first: it races the raster
+           jsr check_space
            dec tick_ctr
            bne +
            lda #TICK_FRAMES
            sta tick_ctr
            jsr script_tick
            jsr agent_draw
            jsr footsteps
+           jsr next_irq
            lda #$ff
            sta $d019
            pla
            tay
            pla
            tax
            pla
            rti

; --- lift scene: the panel split (line 169) -------------------------------------------
; The panel's colours and charset must change between the end of the last
; shaft line (170, display ends at cycle 55) and the panel's first line (171, a
; badline: the CPU stops at cycle 12). The CIA timer (synced by the demo,
; one raster line per period) gives the exact cycle; a sled of cmp #$c9
; then waits 65 - k cycles when entered at byte k (as the demo's beam).
irq_split
            pha
            txa
            pha
            tya
            pha
            ldx #SPLIT_WAIT
-           dex
            bne -
            lda #SPLIT_K
            sec
            sbc $dc04           ; exact cycle from the timer
            sta _j + 1
            lda #PANEL_MC1
            ldx #PANEL_MC2
            ldy #PANEL_BG
_j          jmp split_sled
SPLIT_WAIT  = 8                 ; measured in VICE: the timer read is on line 170, cycle 5-8
SPLIT_K     = 46                ; the store starts on cycle 55 (write on 58); sled entry 32-35

; --- lift: riding ----------------------------------------------------------------------
; Every frame while riding: the original redraws the shaft view in two halves,
; rows 0-6 one frame (one row up), rows 7-13 and the new row 14 the next.
lift_frame
            jsr lfsr_step
            lda sh_phase
            beq _done
            cmp #3
            beq _wind
            cmp #2
            beq _bottom
            inc sh_pos
            ldx #0              ; rows 0-6 <- rows 1-7
            lda #7
            jsr copy_rows
            jsr draw_inner_top
            jsr lift_hum
            lda #2
            sta sh_phase
            rts
_bottom     ldx #7              ; rows 7-13 <- rows 8-14
            lda #7
            jsr copy_rows
            lda sh_pos
            clc
            adc #VIEW_ROWS - 1
            ldx #VIEW_ROWS - 1
            jsr gen_row         ; the new row at the bottom
            lda #1
            sta sh_phase
            lda sh_pos
            cmp sh_target
            bne _done
            lda #3              ; arrived: the hum spins down
            sta sh_phase
            lda #1              ; voice 1 follows one frame later
            sta snd_hold
_done       rts
_wind       jmp lift_wind

; The hum spins down after the lift stops, as in the original: every frame
; the pitch (high byte) drops by 4 (voice 1) and 3 (voice 2), the wobble
; stops; at 0 both waveforms are switched off.
lift_wind   lda snd_v2
            sec
            sbc #3
            bcs +
            lda #0
+           sta snd_v2
            sta $d408
            lda snd_hold
            beq +
            dec snd_hold
            jmp _check
+           lda snd_v1
            sec
            sbc #4
            bcs +
            lda #0
+           sta snd_v1
            sta $d401
_check      lda snd_v1
            ora snd_v2
            bne +
            sta $d404           ; off: no waveform, gate off
            sta $d40b
            sta sh_phase        ; stopped
+           rts

; 3 bit noise as the original's $e1: 5 6 7 3 1 4 2 ...
lfsr_step   lda lfsr3
            lsr a
            eor lfsr3
            and #1
            beq +
            lda #4
+           sta gt
            lda lfsr3
            lsr a
            ora gt
            sta lfsr3
            rts

; The lift hum, as the original ($85b3): voice 1 sawtooth, voice 2 noise; the
; pitch ramps up when the ride starts and wobbles with the 3 bit noise.
lift_hum    lda snd_v1
            cmp #$20
            bcs +
            adc #$04
            sta snd_v1
+           lda snd_v2
            cmp #$18
            bcs +
            adc #$03
            sta snd_v2
+           lda lfsr3
            lsr a
            lsr a
            pha
            eor snd_v1
            sta $d401
            pla
            eor snd_v2
            sta $d408
            lda lfsr3
            lsr a
            ror a
            ror a
            sta $d400
            sta $d407
            lda #$00
            sta $d405
            sta $d40c
            lda #$8f
            sta $d406
            sta $d40d
            lda #$21
            sta $d404
            lda #$81
            sta $d40b
            rts

; Copy A view rows up by one, starting at row X (row X <- row X+1), in the
; scrolling columns 0-16 and 23-39 only (the inside of the shaft stays).
copy_rows   sta gt
_row        lda row_lo,x
            sta dst_s
            sta dst_c
            lda row_lo + 1,x
            sta src_s
            sta src_c
            lda row_hi,x
            sta dst_s + 1
            clc
            adc #>($d800 - M_SCREEN)
            sta dst_c + 1
            lda row_hi + 1,x
            sta src_s + 1
            clc
            adc #>($d800 - M_SCREEN)
            sta src_c + 1
            ldy #16
-           lda (src_s),y
            sta (dst_s),y
            lda (src_c),y
            sta (dst_c),y
            dey
            bpl -
            ldy #39
-           lda (src_s),y
            sta (dst_s),y
            lda (src_c),y
            sta (dst_c),y
            dey
            cpy #22
            bne -
            inx
            dec gt
            bne _row
            rts

; Shaft row A (0 = the top, with the ceiling) into view row X: rock tiles,
; the walls, and corridors from corridor_table.
gen_row     sta gw
            lda row_lo,x
            sta dst_s
            sta dst_c
            lda row_hi,x
            sta dst_s + 1
            clc
            adc #>($d800 - M_SCREEN)
            sta dst_c + 1
            lda gw              ; rock tiles from a seed per tile row
            lsr a               ; (both character rows of a tile row)
            sta rnd
            asl a
            asl a
            asl a
            sec
            sbc rnd             ; * 7
            eor #$5a
            bne +
            lda #1
+           sta rnd
            ldx #15
-           jsr rnd_step
            jsr rnd_step
            and #7
            asl a
            asl a
            sta tiles,x
            dex
            bpl -
            ldx #0              ; 8 tiles left (columns 0-15), 8 right (24-39)
            ldy #0
_tile       cpx #8
            bne +
            ldy #24
+           lda gw              ; the bottom character row of a tile: +1
            and #1
            clc
            adc tiles,x
            sta gk
            adc #2
            sta (dst_s),y       ; left char: k + 2
            lda #1
            sta (dst_c),y
            iny
            lda gk
            sta (dst_s),y       ; right char: k
            lda #1
            sta (dst_c),y
            iny
            inx
            cpx #16
            bne _tile
            ; the walls (column 16 and 23)
            lda gw
            bne +
            lda #$3e            ; the top of the shaft
            bne _wall
+           sec                 ; (row - 1) mod 3
            sbc #1
-           cmp #3
            bcc +
            sbc #3
            bcs -
+           tax
            lda wall_chars,x
_wall       ldy #16
            sta (dst_s),y
            ldy #23
            sta (dst_s),y
            lda #8
            sta (dst_c),y
            ldy #16
            sta (dst_c),y
            ; corridors
            ldx #0
_corr       lda corridor_table,x
            cmp #$ff
            beq _cdone
            sta gt
            lda gw
            sec
            sbc gt
            bcc _cnext
            cmp #8
            bcs _cnext
            sta gk              ; corridor row 0-7
            lda corridor_table + 1,x
            and #CORR_L
            beq +
            lda corridor_table + 2,x
            sta fill_c
            txa
            pha
            lda #0              ; columns 0-16
            ldx #<corr_left
            ldy #>corr_left
            jsr put_corr
            pla
            tax
+           lda corridor_table + 1,x
            and #CORR_R
            beq _cnext
            lda corridor_table + 3,x
            sta fill_c
            txa
            pha
            lda #23             ; columns 23-39
            ldx #<corr_right
            ldy #>corr_right
            jsr put_corr
            pla
            tax
_cnext      inx
            inx
            inx
            inx
            bne _corr
_cdone      rts

wall_chars  .byte $20, $24, $25

rnd_step    lda rnd             ; 8 bit Galois LFSR
            lsr a
            bcc +
            eor #$b8
+           sta rnd
            rts

; Corridor row gk (0-7) of the template at Y/X (lo X, hi Y: 8 x 17 chars,
; then 8 x 17 colours; colour $10 = the corridor's fill colour) into the
; current row at column A.
put_corr    stx src_s
            sty src_s + 1
            sta gt
            lda gk              ; row offset: gk * 17
            asl a
            asl a
            asl a
            asl a
            clc
            adc gk
            clc
            adc src_s
            sta src_s
            bcc +
            inc src_s + 1
+           lda src_s           ; colours: 136 bytes further
            clc
            adc #136
            sta src_c
            lda src_s + 1
            adc #0
            sta src_c + 1
            lda dst_s           ; destination: + column A
            clc
            adc gt
            sta _ds + 1
            sta _dc + 1
            lda dst_s + 1
            adc #0
            sta _ds + 2
            clc
            adc #>($d800 - M_SCREEN)
            sta _dc + 2
            ldy #16
-           lda (src_s),y
_ds         sta $ffff,y
            lda (src_c),y
            cmp #$10
            bne +
            lda fill_c
+
_dc         sta $ffff,y
            dey
            bpl -
            rts

; The inside of the shaft in view rows 0-3 (above the car): the ceiling where
; shaft row 0 is in view, the cables elsewhere.
draw_inner_top
            ldx #0
_r          txa
            clc
            adc sh_pos
            beq +
            lda #6              ; cable row (inner row 1)
            .byte $2c
+           lda #0              ; ceiling (inner row 0)
            jsr put_inner
            inx
            cpx #CAR_ROW
            bne _r
            rts

; Inner row from lift_inner offset A (row * 6) into view row X, columns 17-22.
put_inner   sta gt
            lda row_lo,x
            clc
            adc #17
            sta dst_s
            sta dst_c
            lda row_hi,x
            adc #0
            sta dst_s + 1
            clc
            adc #>($d800 - M_SCREEN)
            sta dst_c + 1
            txa
            pha
            ldx gt
            ldy #0
-           lda lift_inner,x
            sta (dst_s),y
            lda lift_inner + 90,x
            sta (dst_c),y
            inx
            iny
            cpy #6
            bne -
            pla
            tax
            rts

; --- scenes ------------------------------------------------------------------------------
scene_room
            lda #SC_ROOM
            sta scene
            lda #$0b            ; display off while drawing
            sta $d011
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
            lda #ROOM_TEST_BG
            sta $d021
            lda #ROOM_TEST_MC1
            sta $d022
            lda #ROOM_TEST_MC2
            sta $d023
            lda #D018_ROOM
            sta $d018
            lda #0
            sta $d017
            sta $d01c
            sta $d01d
            sta $d01b
            lda #0              ; only the agent's sprites
            sta $d015
            jmp scene_common

scene_lift
            lda #SC_LIFT
            sta scene
            lda #$0b            ; display off while drawing
            sta $d011
            ldx #0              ; the panel: rows 15-24
-           lda lift_panel,x
            sta M_SCREEN + 600,x
            lda lift_panel + 400,x
            sta $d800 + 600,x
            lda lift_panel + 200,x
            sta M_SCREEN + 800,x
            lda lift_panel + 600,x
            sta $d800 + 800,x
            inx
            cpx #200
            bne -
            ldx #0              ; the shaft view from sh_pos
-           txa
            pha
            clc
            adc sh_pos
            jsr gen_row
            pla
            tax
            inx
            cpx #VIEW_ROWS
            bne -
            jsr draw_inner_top
            ldx #CAR_ROW        ; the car and the shaft below it
-           txa
            asl a
            sta gt
            asl a
            clc
            adc gt              ; * 6
            jsr put_inner
            inx
            cpx #VIEW_ROWS
            bne -
            lda #0
            sta sh_phase
            sta snd_v1
            sta snd_v2
            lda #5
            sta lfsr3
            lda #LIFT_BG
            sta $d021
            lda #LIFT_MC1
            sta $d022
            lda #LIFT_MC2
            sta $d023
            lda #D018_LIFT
            sta $d018
            ; sprites: 0 the lines beside the car (multicolor, Y-expanded),
            ; 6 the panel marker, 7 the car hanger
            lda #LIFTSPR_PTR
            sta M_SCREEN + $3f8
            lda #LIFTSPR_PTR + 1
            sta M_SCREEN + $3ff
            lda #LIFTSPR_PTR + 2
            sta M_SCREEN + $3fe
            lda #202
            sta $d000
            lda #94
            sta $d001
            lda #107
            sta $d00c
            lda #186
            sta $d00d
            lda #172
            sta $d00e
            lda #77
            sta $d00f
            lda #2
            sta $d027
            lda #12
            sta $d02d
            lda #1
            sta $d02e
            lda #$0a
            sta $d025
            lda #0
            sta $d026
            sta $d01d
            sta $d01b
            lda #%00000001
            sta $d01c
            sta $d017
            lda #%11000001
            sta $d015
scene_common
            lda #$d8            ; multicolor text, 40 columns
            sta $d016
            lda #1              ; agent colours: white overlay, grey body/legs
            sta $d028
            lda #11
            sta $d029
            sta $d02a
            lda $d010
            and #%11110001
            sta $d010
            lda #$1b            ; display on
            sta $d011
            rts

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
            cmp #C_SCENE
            beq _scene
            cmp #C_RIDE
            beq _ride
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
_ride       iny
            lda (sc_p),y
            sta sh_target
            lda #FR_STAND
            sta ag_frame
            lda #0              ; the hum ramps up from the start
            sta snd_v1
            sta snd_v2
            lda #5              ; the original's SID volume
            sta $d418
            lda #1
            sta sh_phase
            lda #2
            jmp advance
_scene      iny                 ; scene, shaft row, X, Y, facing
            lda (sc_p),y
            pha
            iny
            lda (sc_p),y
            cmp #$ff
            beq +
            sta sh_pos
+           iny
            lda (sc_p),y
            sta ag_x
            iny
            lda (sc_p),y
            sta ag_x + 1
            iny
            lda (sc_p),y
            sta ag_y
            iny
            lda (sc_p),y
            sta ag_face
            lda #FR_STAND
            sta ag_frame
            lda #7
            jsr advance
            pla
            cmp #SC_LIFT
            beq +
            jsr scene_room
            jmp script_next
+           jsr scene_lift
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
            cmp #C_RIDE
            beq _ride
            ; C_STAND
            dec sc_wait
            bne +
            jmp script_next
+           rts
_ride       lda sh_phase        ; arrived? (stopped, or the hum spinning down)
            beq +
            cmp #3
            bne ++
+           jmp script_next
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

; --- the shaft ------------------------------------------------------------------------
; Corridors: shaft row of the top edge, sides, fill colour left, right.
; A corridor is in line with the car when view row 4 shows its top edge.
corridor_table
            .byte 4, CORR_R, 0, 7
            .byte 28, CORR_L, 5, 0
            .byte 76, CORR_L | CORR_R, 3, 3
            .byte 124, CORR_R, 0, 5
            .byte 172, CORR_L, 7, 0
            .byte $ff

row_lo      .for r := 0, r < VIEW_ROWS + 1, r += 1
            .byte <(M_SCREEN + r * 40)
            .next
row_hi      .for r := 0, r < VIEW_ROWS + 1, r += 1
            .byte >(M_SCREEN + r * 40)
            .next
tiles       .fill 16

; --- the script (stage 2): down the shaft, through a corridor into a room and
; back, further down, then from the top again --------------------------------------
mission_script
            .byte C_SCENE, SC_LIFT, 0
            .word LIFT_AGENT_X
            .byte LIFT_AGENT_Y, FACE_RIGHT
            .byte C_STAND, 25
            .byte C_RIDE, 28 - CAR_ROW          ; to the left corridor
            .byte C_STAND, 8
            .byte C_FACE, FACE_LEFT
            .byte C_RUN
            .word 10
            .byte C_SCENE, SC_ROOM, $ff         ; the room's entrance: bottom right
            .word 330
            .byte floor_y(24), FACE_LEFT
            .byte C_RUN
            .word 262
            .byte C_FLIP
            .byte C_RUN
            .word 160
            .byte C_STAND, 20
            .byte C_FACE, FACE_RIGHT
            .byte C_STAND, 6
            .byte C_RUN
            .word 340
            .byte C_SCENE, SC_LIFT, $ff         ; back out into the corridor
            .word LIFT_AGENT_X - 5 * 32         ; runs back to exactly LIFT_AGENT_X
            .byte LIFT_AGENT_Y, FACE_RIGHT
            .byte C_RUN
            .word LIFT_AGENT_X
            .byte C_STAND, 10
            .byte C_RIDE, 76 - CAR_ROW          ; further down
            .byte C_STAND, 25
            .byte C_GOTO
            .word mission_script

            .align 256
rev_bits                        ; bit-reversed bytes, for mirroring hires sprites
            .for i := 0, i < 256, i += 1
            .byte ((i >> 7) & 1) | ((i >> 5) & 2) | ((i >> 3) & 4) | ((i >> 1) & 8) | ((i << 1) & 16) | ((i << 3) & 32) | ((i << 5) & 64) | ((i << 7) & 128)
            .next

            .align 256
split_sled  .fill 62, $c9       ; entry k waits 65 - k cycles
            .byte $c5, $ea
split_store sta $d022           ; line 170, cycle 58 (right border)
            stx $d023
            sty $d021           ; line 171, cycle 3
            lda #D018_PANEL
            sta $d018           ; line 171, cycle 9
            lda #<irq_main
            sta $fffe
            lda #>irq_main
            sta $ffff
            lda #MAIN_LINE
            sta $d012
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
            * = M_LIFTSPR
            .binary "../assets/im/lift_sprites.bin"

            * = M_CHARSET
            .binary "../assets/im/charset_rooms.bin"
            .cerror * != $9000, "room charset must end at $9000 (char ROM area follows)"

            * = $9000           ; CPU-only area (the VIC sees char ROM here)
room_test_screen
            .binary "../assets/im/room_test_screen.bin"
room_test_colram
            .binary "../assets/im/room_test_colram.bin"
lift_panel  .binary "../assets/im/lift_panel.bin"       ; 400 chars, 400 colours
lift_inner  .binary "../assets/im/lift_inner.bin"       ; 15 x 6 chars, 15 x 6 colours
corr_left   .binary "../assets/im/corr_left.bin"        ; 8 x 17 chars, 8 x 17 colours
corr_right  .binary "../assets/im/corr_right.bin"
            .cerror * > $a000, "room data beyond $9fff"

            * = M_LIFTCHR
            .binary "../assets/im/charset_lift.bin"

            * = M_AGENT
            .binary "../assets/im/agent_sprites.bin"
            .cerror * != $b800, "agent sprites must be 64 blocks"

            * = M_PANELCHR
            .binary "../assets/im/charset_panel.bin"
            .cerror * != $c000, "panel charset must be 2 KB"
