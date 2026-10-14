; ---------------------------------------------------------------------------
; VIPP Mission: the pocket computer's map, as in the original.
; Included by mission.asm after mission_danger.asm ($c000 segment).
;
; The green screen of the panel (rows 17-22, columns 10-26 of the lift
; screen) is a 136 x 48 pixel bitmap: each cell has its own character in the
; panel charset, $8b + row * 17 + column, shown only once something is drawn
; in it (else the empty $fc). Ink (1) is the green, lines are cleared bits.
; Drawn as in the original: the shaft as a 2 px line, cell by cell as the
; lift reveals it, the corridors as 3 px stubs, a visited room as a filled
; 8 x 5 block beside its corridor; 6 shaft rows per map pixel. The marker
; (sprite 6) follows the lift. (Our single shaft is drawn in the middle,
; the original's first shaft is at the map's left edge.)
; ---------------------------------------------------------------------------

MAP_COLS    = 17
MAP_ROWS    = 6
MAP_CELLS   = MAP_COLS * MAP_ROWS
MAP_CHAR0   = $8b
MAP_EMPTY   = $fc
MAP_SCREEN  = M_SCREEN + 17 * 40 + 10
MAP_BITS    = M_PANELCHR + MAP_CHAR0 * 8
SHAFT_MX    = 64                ; the shaft line: map x 64-65
MARKER_X0   = 104               ; sprite X of map x 0 (the original: x 3 -> 107)
MARKER_Y0   = 186               ; sprite Y of map y 0 (screen row 17)

; zero page
mx          = $68
my          = $69
map_drawn    = $6a               ; shaft cell rows drawn so far
map_p       = $6b               ; 2

; Every loop starts with an empty map.
map_reset   ldx #0              ; all 102 characters (816 bytes) green
            lda #$ff
-           sta MAP_BITS,x
            sta MAP_BITS + $100,x
            sta MAP_BITS + $200,x
            inx
            bne -
            ldx #MAP_CELLS * 8 - $300 - 1
-           sta MAP_BITS + $300,x
            dex
            bpl -
            .cerror MAP_BITS + MAP_CELLS * 8 > M_PANELCHR + $f1 * 8, "map characters overlap the panel's own"
            ldx #MAP_CELLS - 1
            lda #0
-           sta map_used,x
            dex
            bpl -
            sta map_drawn
            rts

; Clear the map pixel (mx, my), the cell becomes visible.
map_plot    lda my
            lsr a
            lsr a
            lsr a
            tax
            lda mx
            lsr a
            lsr a
            lsr a
            clc
            adc map_row17,x     ; cell = row * 17 + column
            tax
            lda #1
            sta map_used,x
            txa                 ; its bitmap: MAP_BITS + cell * 8 + (my & 7)
            sta map_p
            lda #0
            asl map_p
            rol a
            asl map_p
            rol a
            asl map_p
            rol a
            sta map_p + 1
            lda my
            and #7
            clc
            adc map_p
            sta map_p
            lda map_p + 1
            adc #>MAP_BITS
            sta map_p + 1
            lda map_p
            clc
            adc #<MAP_BITS
            sta map_p
            bcc +
            inc map_p + 1
+           lda mx
            and #7
            tax
            ldy #0
            lda (map_p),y
            and map_clear,x
            sta (map_p),y
            rts
map_row17   .for r := 0, r < MAP_ROWS, r += 1
            .byte r * MAP_COLS
            .next
map_clear   .byte $7f, $bf, $df, $ef, $f7, $fb, $fd, $fe

; A horizontal run: A pixels from (mx, my) to the right.
map_hline   sta box_tmp
-           jsr map_plot
            inc mx
            dec box_tmp
            bne -
            rts

; The shaft down to the view's bottom: whole cell rows, as the original.
map_reveal  lda sh_pos          ; map y of the view's bottom row: (pos + 14) / 6
            clc
            adc #VIEW_ROWS - 1
            jsr div6
            lsr a               ; its cell row
            lsr a
            lsr a
            cmp #MAP_ROWS
            bcc +
            lda #MAP_ROWS - 1
+           cmp map_drawn
            bcc _none
            ; draw cell row map_drawn .. A
            sta map_last
-           lda map_drawn
            jsr map_shaft_cells
            inc map_drawn
            lda map_drawn
            cmp map_last
            bcc -
            beq -
            sec                 ; drawn something
            rts
_none       clc
            rts
map_last    .byte 0

; Cell row A: the shaft line and the corridor stubs in it.
map_shaft_cells
            asl a
            asl a
            asl a
            sta my
            sta rb_k            ; first pixel row
            clc
            adc #8
            sta map_tmp         ; end
-           lda #SHAFT_MX
            sta mx
            lda #2
            jsr map_hline
            inc my
            lda my
            cmp map_tmp
            bne -
            ldx #0              ; corridors: map y = (row + 2) / 6
_corr       lda corridor_table,x
            cmp #$ff
            beq _done
            clc
            adc #2
            jsr div6
            cmp rb_k
            bcc _next
            cmp map_tmp
            bcs _next
            sta my
            lda corridor_table + 1,x
            and #CORR_L
            beq +
            lda #SHAFT_MX - 3
            sta mx
            txa
            pha
            lda #3
            jsr map_hline
            pla
            tax
+           lda corridor_table + 1,x
            and #CORR_R
            beq _next
            lda #SHAFT_MX + 2
            sta mx
            txa
            pha
            lda #3
            jsr map_hline
            pla
            tax
_next       inx
            inx
            inx
            inx
            bne _corr
_done       rts
map_tmp     .byte 0

; The room just entered (room_cur, entered facing ag_face): a filled 8 x 5
; block beside its corridor.
map_room    lda room_cur        ; its corridor: corridor_table entry room_cur
            asl a
            asl a
            tax
            lda corridor_table,x
            clc
            adc #2
            jsr div6
            sta my
            lda #SHAFT_MX + 5   ; entered facing right: the room is right
            bit ag_face
            bpl +
            lda #SHAFT_MX - 3 - 8
+           sta rb_k
            lda #5
            sta map_tmp
-           lda rb_k
            sta mx
            lda #8
            jsr map_hline
            inc my
            dec map_tmp
            bne -
            rts

; A / 6 (A < 256)
div6        ldy #0
-           cmp #6
            bcc +
            sbc #6
            iny
            bne -
+           tya
            rts

; Show the drawn cells on the panel (lift scene).
map_show    lda #<MAP_SCREEN
            sta map_p
            lda #>MAP_SCREEN
            sta map_p + 1
            ldx #0              ; cell
_row        ldy #0              ; column
-           lda map_used,x
            beq +
            txa
            clc
            adc #MAP_CHAR0
            .byte $2c
+           lda #MAP_EMPTY
            sta (map_p),y
            inx
            iny
            cpy #MAP_COLS
            bne -
            lda map_p
            clc
            adc #40
            sta map_p
            bcc +
            inc map_p + 1
+           cpx #MAP_CELLS
            bne _row
            rts

; The marker (sprite 6) where the lift is: 1 px per 6 shaft rows.
map_marker  lda #MARKER_X0 + SHAFT_MX
            sta $d00c
            lda sh_pos
            jsr div6
            clc
            adc #MARKER_Y0
            sta $d00d
            rts

map_used    .fill MAP_CELLS
