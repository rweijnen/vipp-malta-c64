; ---------------------------------------------------------------------------
; VIPP Mission, part 2 ($c000-$cfff): rooms, robots, the security terminals
; and searching furniture. Included by mission.asm.
;
; Rooms: built by the original (tools/im/extract_rooms.py), packed by
; tools/im/gen_mission.py: run length ($ff n v, $ff 0 = end), screen then
; colours. The packed rooms are mostly in the RAM under the I/O area
; ($d000-$dfff), read with $01 = $34 (all RAM) one byte at a time.
; ---------------------------------------------------------------------------

; zero page (mission part 2)
up_src      = $40               ; 2: unpack source
up_dst      = $42               ; 2: unpack destination
up_w        = $44               ; bytes left in this row
up_width    = $45               ; row width
up_skip     = $46               ; added to the destination after a row
room_cur    = $47               ; room index 0-4 (into ROOM_ORDER)
rb_k        = $48
search_left = $49               ; search ticks to go
search_len  = $4a
box_pos     = $4b               ; 2: screen address of the box's top left
box_tmp     = $4d
up_val      = $4e
search_phase = $4f              ; 0 the bar runs, 1 the result is shown
search_res  = $67               ; result: 0 "Nothing here.", 1 the VIPP find
RESULT_TICKS = 30

ROBOT_PTR   = (M_ROBOTSPR & $3fff) / 64
TERMSPR_PTR = (M_TERMSPR & $3fff) / 64
ROBOT_SPEED = 2                 ; px per tick
ROBOT_PAUSE = 8                 ; ticks at the end of a walk before turning
FR_FACE     = 15                ; the agent's back to the camera (searching)

            * = $c000

; --- unpacking ----------------------------------------------------------------------
; Unpack from up_src to up_dst until the end mark, rows of up_width bytes
; with up_skip added after each row.
unpack      lda up_width
            sta up_w
_next       jsr up_get
            cmp #$ff
            bne _one
            jsr up_get          ; run: count (0 = the end), value
            tax
            beq _done
            jsr up_get
            sta up_val
-           lda up_val
            jsr up_put
            dex
            bne -
            beq _next
_one        jsr up_put
            jmp _next
_done       rts

; a source byte (the RAM under the I/O area too); keeps X
up_get      ldy #$34
            sty $01
            ldy #0
            lda (up_src),y
            ldy #$35
            sty $01
            inc up_src
            bne +
            inc up_src + 1
+           rts

; write A, next position (a new row after up_width bytes); keeps X
up_put      ldy #0
            sta (up_dst),y
            inc up_dst
            bne +
            inc up_dst + 1
+           dec up_w
            bne ++
            lda up_skip
            clc
            adc up_dst
            sta up_dst
            bcc +
            inc up_dst + 1
+           lda up_width
            sta up_w
+           rts

; full screen + colours from up_src (rooms, the terminal frame)
unpack_screen
            lda #<M_SCREEN
            sta up_dst
            lda #>M_SCREEN
            sta up_dst + 1
            lda #40
            sta up_width
            lda #0
            sta up_skip
            jsr unpack
            lda #<$d800
            sta up_dst
            lda #>$d800
            sta up_dst + 1
            jmp unpack

; --- rooms ----------------------------------------------------------------------------
; Draw room room_cur: screen, colours, colours of the room and its robots.
draw_room   lda #$0b            ; display off while drawing
            sta $d011
            ldx room_cur
            lda room_lo,x
            sta up_src
            lda room_hi,x
            sta up_src + 1
            jsr unpack_screen
            ldx room_cur
            lda room_bg,x
            sta $d021
            lda room_mc1,x
            sta $d022
            lda room_mc2,x
            sta $d023
            lda room_smc1,x     ; the robots: multicolor sprites 4-7
            sta $d025
            lda room_smc2,x
            sta $d026
            lda room_rcol,x
            sta $d02b
            sta $d02c
            sta $d02d
            sta $d02e
            lda #D018_ROOM
            sta $d018
            lda #0
            sta $d017
            sta $d01d
            sta $d01b
            lda #%11110000
            sta $d01c
            lda #0
            sta $d015
            jmp danger_room

; Enter room room_cur: draw it, the robots at their places.
scene_room  lda #SC_ROOM
            sta scene
            jsr draw_room
            jsr robots_init
            jsr robots_draw
            jmp scene_common

; Back from the terminal: the room as it was (robots where they were).
scene_back  lda #SC_ROOM
            sta scene
            jsr draw_room
            jsr robots_draw
            jmp scene_common

; --- robots ---------------------------------------------------------------------------
; Up to 4 per room on sprites 4-7, from the original's room data. They walk
; their platform, wait at its end, turn (7 frames, 0 = facing right, 6 =
; facing left) and walk back.
robots_init lda room_cur
            asl a
            asl a
            sta rb_k            ; table index room * 4
            ldx #0
-           ldy rb_k
            lda rob_x_lo,y
            sta rbx_lo,x
            lda rob_x_hi,y
            sta rbx_hi,x
            lda rob_y,y
            sta rby,x
            lda rob_min_lo,y
            sta rbmin_lo,x
            lda rob_min_hi,y
            sta rbmin_hi,x
            lda rob_max_lo,y
            sta rbmax_lo,x
            lda rob_max_hi,y
            sta rbmax_hi,x
            lda rob_type,y      ; speed 1 or 2 from the type (variety)
            and #1
            clc
            adc #1
            sta rbspeed,x
            lda rob_type,y      ; first direction from the type too
            and #2
            beq +
            lda #6              ; facing left
+           sta rbframe,x
            lda #0
            sta rbstate,x
            sta rbtimer,x
            sta rbcool,x
            inc rb_k
            inx
            cpx #4
            bne -
            ldx room_cur
            lda room_nrob,x
            sta rb_n
            rts

robots_tick ldx rb_n
            bne +
            rts
+           dex
_robot      lda rbstate,x
            beq _walk
            cmp #1
            beq _pause
            cmp #3              ; firing (zap_tick)
            bne +
            jmp _next
+
            ; turning: a frame per tick to the other side
            lda rbframe,x
            cmp rbtarget,x
            beq _turned
            bcc +
            dec rbframe,x
            jmp _next
+           inc rbframe,x
            jmp _next
_turned     lda #0
            sta rbstate,x
            jmp _next
_pause      dec rbtimer,x
            bne _next
            lda #2              ; turn to face the other way
            sta rbstate,x
            lda rbframe,x
            beq +
            lda #0
            .byte $2c
+           lda #6
            sta rbtarget,x
            jmp _next
_walk       lda rbframe,x       ; frame 0 walks right, 6 left
            bne _left
            clc                 ; right
            lda rbx_lo,x
            adc rbspeed,x
            sta rbx_lo,x
            bcc +
            inc rbx_hi,x
+           lda rbmax_lo,x      ; at the end?
            cmp rbx_lo,x
            lda rbmax_hi,x
            sbc rbx_hi,x
            bcs _next
            lda rbmax_lo,x
            sta rbx_lo,x
            lda rbmax_hi,x
            sta rbx_hi,x
            jmp _end
_left       sec
            lda rbx_lo,x
            sbc rbspeed,x
            sta rbx_lo,x
            bcs +
            dec rbx_hi,x
+           lda rbx_lo,x        ; at the end?
            cmp rbmin_lo,x
            lda rbx_hi,x
            sbc rbmin_hi,x
            bcs _next
            lda rbmin_lo,x
            sta rbx_lo,x
            lda rbmin_hi,x
            sta rbx_hi,x
_end        lda #1
            sta rbstate,x
            lda #ROBOT_PAUSE
            sta rbtimer,x
_next       dex
            bmi +
            jmp _robot
+           rts

robots_draw lda #0
            sta box_tmp         ; enable bits
            sta rb_k            ; X high bits
            ldx rb_n
            beq _show
            dex
-           txa
            asl a
            tay                 ; sprite (4 + x) register offset
            lda rbx_lo,x
            sta $d008,y
            lda rby,x
            sta $d009,y
            lda rbframe,x
            clc
            adc #ROBOT_PTR
            sta M_SCREEN + $3fc,x
            lda box_tmp
            ora rb_bit,x
            sta box_tmp
            lda rbx_hi,x
            beq +
            lda rb_k
            ora rb_bit,x
            sta rb_k
+           dex
            bpl -
_show       lda $d010
            and #%00001111
            ora rb_k
            sta $d010
            lda $d015
            and #%00001111
            ora box_tmp
            sta $d015
            rts

rb_bit      .byte $10, $20, $40, $80
rb_n        .byte 0
rbx_lo      .fill 4
rbx_hi      .fill 4
rby         .fill 4
rbmin_lo    .fill 4
rbmin_hi    .fill 4
rbmax_lo    .fill 4
rbmax_hi    .fill 4
rbspeed     .fill 4
rbframe     .fill 4
rbstate     .fill 4             ; 0 walking, 1 waiting at the end, 2 turning, 3 firing
rbtimer     .fill 4
rbtarget    .fill 4

; --- the security terminals -------------------------------------------------------
; Terminal A (0-4): the original's terminal screen with a Parallels product.
scene_term  pha
            jsr term_sprites_back
            lda #SC_TERM
            sta scene
            lda #$0b            ; display off while drawing
            sta $d011
            lda #<term_frame
            sta up_src
            lda #>term_frame
            sta up_src + 1
            jsr unpack_screen
            pla                 ; the text: rows 3-17, columns 6-33
            tax
            lda term_lo,x
            sta up_src
            lda term_hi,x
            sta up_src + 1
            lda #<(M_SCREEN + 3 * 40 + 6)
            sta up_dst
            lda #>(M_SCREEN + 3 * 40 + 6)
            sta up_dst + 1
            lda #28
            sta up_width
            lda #12
            sta up_skip
            jsr unpack
            lda #TERM_BORDER
            sta $d020
            lda #TERM_BG
            sta $d021
            lda #TERM_MC1
            sta $d022
            lda #TERM_MC2
            sta $d023
            lda #D018_LIFT      ; the terminal font is the lift charset
            sta $d018
            ldx #7              ; the monitor's corners: 8 hires sprites
-           txa
            asl a
            tay
            lda term_spr_y,x
            sta $d001,y
            lda term_spr_x,y
            sta $d000,y
            lda term_spr_blk,x
            clc
            adc #TERMSPR_PTR
            sta M_SCREEN + $3f8,x
            lda #TERM_SPR_COL
            sta $d027,x
            dex
            bpl -
            ldx #7              ; X high bits
            lda #0
            sta box_tmp
-           txa
            asl a
            tay
            lda term_spr_x + 1,y
            beq +
            lda box_tmp
            ora spr_bits,x
            sta box_tmp
+           dex
            bpl -
            lda box_tmp
            sta $d010
            lda #0
            sta $d01c
            sta $d017
            sta $d01d
            sta $d01b
            lda #$ff
            sta $d015
            lda #$1b
            sta $d011
            lda #$d8
            sta $d016
            rts
spr_bits    .byte 1, 2, 4, 8, 16, 32, 64, 128

; --- searching ------------------------------------------------------------------------
; The original's box above the agent: 8 x 4 characters, the middle rows
; characters 0-15 of the room charset ("Searching" and a bar that empties
; from the left), white. The agent has his back to the camera; voice 3 ticks.
SEARCH_BAR_PX = 64

search_start
            sta search_len
            sta search_left
            lda #0
            sta search_phase
            ldx #127            ; the box's characters, bar full
-           lda search_box,x
            sta M_CHARSET,x
            dex
            bpl -
            ; where: 8 rows above the agent's floor (clear of furniture up to
            ; 4 rows high, as the candy machine), around his middle
            lda ag_y            ; floor row = (y - 10) / 8; top = floor - 8
            sec
            sbc #10
            lsr a
            lsr a
            lsr a
            sec
            sbc #8
            bcs +
            lda #0              ; top floors: the screen's first row
+           tax
            lda row_lo,x
            sta box_pos
            lda row_hi,x
            sta box_pos + 1
            lda ag_x            ; column = (x - 24 + 12) / 8 - 3, kept 1-31
            sec
            sbc #12
            sta box_tmp
            lda ag_x + 1
            sbc #0
            lsr a
            lda box_tmp
            ror a
            lsr a
            lsr a
            sec
            sbc #3
            bcs +
            lda #1
+           cmp #1
            bcs +
            lda #1
+           cmp #32
            bcc +
            lda #31
+           clc
            adc box_pos
            sta box_pos
            bcc +
            inc box_pos + 1
+           ; save what is under the box, then draw it
            ldx #0
            ldy #0
_save       jsr box_row_ptr
            lda (up_dst),y
            sta box_save,x
            lda (up_src),y
            sta box_save + 32,x
            inx
            iny
            cpy #8
            bne _save
            ldy #0
            cpx #32
            bne _save
            ldx #0              ; rows: solid, chars 0-7, chars 8-15, solid
            ldy #0
_draw       jsr box_row_ptr
            lda box_chars,x
            sta (up_dst),y
            lda #1
            sta (up_src),y
            inx
            iny
            cpy #8
            bne _draw
            ldy #0
            cpx #32
            bne _draw
            lda #FR_FACE
            sta ag_frame
            lda #$00            ; the tick: voice 3, pulse
            sta $d40e
            lda #$04
            sta $d40f
            sta $d40e
            lda #$00
            sta $d410
            lda #$08
            sta $d411
            lda #$00
            sta $d413
            lda #$c0
            sta $d414
            rts

; up_dst = screen, up_src = colour RAM of box row X / 8 (keeps X, Y)
box_row_ptr txa
            pha
            lsr a
            lsr a
            lsr a
            tax
            lda box_pos
            clc
            adc box_row40,x
            sta up_dst
            sta up_src
            lda box_pos + 1
            adc #0
            sta up_dst + 1
            clc
            adc #>($d800 - M_SCREEN)
            sta up_src + 1
            pla
            tax
            rts
box_row40   .byte 0, 40, 80, 120
box_chars   .byte $52, $52, $52, $52, $52, $52, $52, $52
            .byte 0, 1, 2, 3, 4, 5, 6, 7
            .byte 8, 9, 10, 11, 12, 13, 14, 15
            .byte $52, $52, $52, $52, $52, $52, $52, $52
box_save    .fill 64

; one tick of searching: the bar, the tick sound, then the result for a
; while; C = 1 when done
search_tick lda search_phase
            beq _bar
            dec search_left     ; the result is shown
            bne +
            jsr box_remove
            lda #0
            sta search_phase
            sec
            rts
+           clc
            rts
_bar        lda search_left
            and #1              ; tick on, tick off
            beq +
            lda #$41
            .byte $2c
+           lda #$80
            sta $d412
            dec search_left
            beq _done
            ; empty pixels: 64 * (len - left) / len, by repeated subtraction
            lda search_len
            sec
            sbc search_left     ; done ticks
            ldx #0              ; px = done * 64 / len
            sta box_tmp
            lda #0
            ldy #6              ; * 64
-           asl box_tmp
            rol a
            dey
            bne -
            ; A:box_tmp = done * 64; divide by len
            sta rb_k
-           lda box_tmp
            sec
            sbc search_len
            tay
            lda rb_k
            sbc #0
            bcc +
            sta rb_k
            sty box_tmp
            inx
            bne -
+           txa                 ; X = empty pixels
            jsr bar_draw
            clc
            rts
_done       lda #$80
            sta $d412
            jsr show_result
            lda #RESULT_TICKS
            sta search_left
            inc search_phase
            clc
            rts

; The result in the box: its 8 x 4 screen codes and characters $00-$11
; (the original's "Nothing here.", or the VIPP find in the same style).
show_result lda search_res
            beq +
            lda #<res_find
            ldx #>res_find
            bne ++
+           lda #<res_nothing
            ldx #>res_nothing
+           sta m_p
            stx m_p + 1
            ldy #32             ; the characters
-           lda (m_p),y
            sta M_CHARSET - 32,y
            iny
            cpy #32 + 18 * 8
            bne -
            ldx #0              ; the layout
            ldy #0
_row        jsr box_row_ptr
            sty box_tmp
            txa
            tay
            lda (m_p),y
            ldy box_tmp
            sta (up_dst),y
            lda #1
            sta (up_src),y
            inx
            iny
            cpy #8
            bne _row
            ldy #0
            cpx #32
            bne _row
            rts

; the bar (pixel rows 5-7 of chars 8-15): A pixels empty from the left
bar_draw    sta box_tmp         ; empty pixels left
            ldx #0              ; 8 * char (chars 8-15)
_c          lda box_tmp
            cmp #8
            bcc +
            lda #$00            ; all 8 empty
            beq ++
+           tay
            lda bar_mask,y      ; 0-7 empty from the left
+           sta M_CHARSET + 8 * 8 + 5,x
            sta M_CHARSET + 8 * 8 + 6,x
            sta M_CHARSET + 8 * 8 + 7,x
            lda box_tmp
            sec
            sbc #8
            bcs +
            lda #0
+           sta box_tmp
            txa
            clc
            adc #8
            tax
            cpx #64
            bne _c
            rts
bar_mask    .byte $ff, $7f, $3f, $1f, $0f, $07, $03, $01

box_remove  ldx #0
            ldy #0
-           jsr box_row_ptr
            lda box_save,x
            sta (up_dst),y
            lda box_save + 32,x
            sta (up_src),y
            inx
            iny
            cpy #8
            bne -
            ldy #0
            cpx #32
            bne -
            rts

