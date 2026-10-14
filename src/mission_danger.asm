; ---------------------------------------------------------------------------
; VIPP Mission: robots fire, and what touches the agent kills him, as in the
; original. Included by mission.asm after mission_rooms.asm ($c000 segment).
;
; The zap: sprite 0, X-expanded, the original's bolt (its sprite blocks
; $14-$17, animating), from the robot's gun 48 px toward the side it faces.
; A robot fires when the agent is on its floor, in front of it and close; it
; stands while firing, then cools down.
;
; Hits: boxes, not the sprite collision register (the agent's three sprites
; always overlap each other). Robot: 16 x 21; zap: the bolt's band; agent:
; standing/running 10 x 40; curled up in a somersault only the ball (so a
; somersault in time clears a robot or a bolt, as in the original).
;
; Death (the original, $95e8): the agent's three sprite blocks are copied
; ($9720), he flashes white / light grey against grey / dark grey with the
; crackle 34 times ($975b, $979a: voice 2 pulse + voice 3 noise, random
; volume 0-7), then disintegrates: 33 rounds of random single pixels erased
; from his blocks ($97d7), with the crackle. He comes back at the room's door,
; the robots back at their places.
; ---------------------------------------------------------------------------

ZAP_PTR     = TERMSPR_PTR       ; the zap's 4 blocks are copied there in rooms
DEATH_PTR   = LIFTSPR_PTR       ; the dying agent's 3 blocks: there in rooms
ZAP_TICKS   = 16                ; a robot fires this long
ZAP_COOL    = 30                ; then this long not
ZAP_RANGE   = 56                ; px: fires when the agent is within the bolt's reach
DEATH_FLASHES = 34
DEATH_ROUNDS = 33
DEATH_PAUSE = 25                ; frames with nothing before he is back

; zero page
zap_rob     = $50               ; robot firing (0-3), $ff none
zap_anim    = $51
dying       = $52               ; 0, 1 flashing, 2 disintegrating, 3 pause
death_cnt   = $53
death_sub   = $54
rnd2        = $55
ab_l        = $56               ; 2: agent box left X
ab_r        = $58               ; 2: right X
ab_t        = $5a               ; top Y
ab_b        = $5b               ; bottom Y
ob_l        = $5c               ; 2: other box
ob_r        = $5e               ; 2
ob_t        = $60
ob_b        = $61
entry_x     = $62               ; 2: the agent's door in this room
entry_y     = $64
entry_face  = $65
death_go    = $66               ; 2: the script after a death (C_ONDEATH)

; --- per room ----------------------------------------------------------------------
; Entering a room (and back from the terminal): the zap's blocks in place,
; nobody firing.
danger_room ldx #0
-           lda zap_blocks,x
            sta M_TERMSPR,x
            inx
            bne -
            lda #$ff
            sta zap_rob
            ldx #3
-           lda #0
            sta rbcool,x
            lda rbstate,x       ; a robot that was firing walks on
            cmp #3
            bne +
            lda #0
            sta rbstate,x
+           dex
            bpl -
            lda #0
            sta dying
            lda $d015
            and #%11111110
            sta $d015
            rts

; The lift's sprites back (the dying agent's blocks used their place).
lift_sprites_back
            ldx #191
-           lda lift_spr_stash,x
            sta M_LIFTSPR,x
            dex
            cpx #$ff
            bne -
            rts

; The terminal's corner sprites back (the zap used their place).
term_sprites_back
            ldx #0
-           lda term_spr_stash,x
            sta M_TERMSPR,x
            lda term_spr_stash + 128,x
            sta M_TERMSPR + 128,x
            lda term_spr_stash + 256,x
            sta M_TERMSPR + 256,x
            inx
            cpx #128
            bne -
            rts

; --- robots firing -----------------------------------------------------------------
; Once per tick after robots_tick: start / keep / end a zap.
zap_tick    ldx #3
-           lda rbcool,x
            beq +
            dec rbcool,x
+           dex
            bpl -
            lda zap_rob
            bmi _look
            tax                 ; firing: count down
            dec rbtimer,x
            bne _draw
            lda #0              ; done: walk on, cool down
            sta rbstate,x
            lda #ZAP_COOL
            sta rbcool,x
            lda #$ff
            sta zap_rob
            lda $d015
            and #%11111110
            sta $d015
            jmp zap_quiet
_look       ldx rb_n            ; who could fire?
            beq _none
            dex
_rob        lda rbstate,x       ; walking or waiting, not turning
            cmp #2
            bcs _next
            lda rbcool,x
            bne _next
            lda rby,x           ; the agent's floor? (his feet = robot's feet)
            sec
            sbc #21
            cmp ag_y
            bne _next
            ; distance and side: dx = agent - robot
            sec
            lda ag_x
            sbc rbx_lo,x
            sta ob_l
            lda ag_x + 1
            sbc rbx_hi,x
            sta ob_l + 1
            bmi _left
            lda rbframe,x       ; agent to the right: the robot faces right?
            bne _next
            lda ob_l + 1
            bne _next
            lda ob_l
            cmp #ZAP_RANGE
            bcs _next
            bcc _fire
_left       lda rbframe,x       ; agent to the left: faces left?
            cmp #6
            bne _next
            lda ob_l + 1
            cmp #$ff
            bne _next
            lda ob_l
            cmp #256 - ZAP_RANGE
            bcc _next
_fire       stx zap_rob
            lda #3              ; firing
            sta rbstate,x
            lda #ZAP_TICKS
            sta rbtimer,x
            jmp _draw
_next       dex
            bpl _rob
_none       rts
_draw       inc zap_anim
            jsr zap_box
            lda ob_l            ; sprite 0: the bolt
            sta $d000
            lda ob_l + 1
            and #1
            sta box_tmp
            lda $d010
            and #%11111110
            ora box_tmp
            sta $d010
            ldx zap_rob
            lda rby,x
            sta $d001
            lda zap_anim
            and #3
            clc
            adc #ZAP_PTR
            sta M_SCREEN + $3f8
            lda #1
            sta $d027
            lda $d01d
            ora #1
            sta $d01d
            lda $d015
            ora #1
            sta $d015
            jmp zap_crackle

; The zap's box (ob_*) for robot zap_rob: 48 px from the gun toward the side
; it faces (in the original: 28 px left of a robot facing left).
zap_box     ldx zap_rob
            lda rbframe,x
            bne _l
            clc                 ; facing right: from robot X + 4
            lda rbx_lo,x
            adc #4
            sta ob_l
            lda rbx_hi,x
            adc #0
            sta ob_l + 1
            jmp _w
_l          sec                 ; facing left: from robot X - 28
            lda rbx_lo,x
            sbc #28
            sta ob_l
            lda rbx_hi,x
            sbc #0
            sta ob_l + 1
_w          clc
            lda ob_l
            adc #47
            sta ob_r
            lda ob_l + 1
            adc #0
            sta ob_r + 1
            lda rby,x
            clc
            adc #5
            sta ob_t
            adc #10
            sta ob_b
            rts

; The original's crackle ($979a): voice 2 pulse, voice 3 noise, random volume.
zap_crackle lda #0
            sta $d407
            sta $d40e
            sta $d40c
            sta $d413
            sta $d409
            lda #$f0
            sta $d40d
            lda #$0f
            sta $d40a
            lda #$70
            sta $d414
            lda #$04
            sta $d408
            lda #$e0
            sta $d40f
            jsr rnd_next
            and #7
            sta $d418
            lda #$41
            sta $d40b
            lda #$81
            sta $d412
            rts

zap_quiet   lda #$08
            sta $d40b
            sta $d412
            lda #5
            sta $d418
            rts

rnd_next    lda rnd2            ; 8 bit Galois LFSR
            lsr a
            bcc +
            eor #$b8
+           sta rnd2
            rts

; --- hits ----------------------------------------------------------------------------
; The agent's box (ab_*) for his current frame.
agent_box   lda ag_frame
            cmp #16
            bcc _stand
            ; somersault: the legs piece is the ball
            clc
            adc #168            ; ag_dx3 / ag_dy3 index: frame + 2 * 84 (table layout)
            tay
            lda ag_dx1,y        ; dx of piece 3 (signed, mirrored facing left)
            bit ag_face
            bpl +
            eor #$ff
            clc
            adc #1
+           sta ob_t            ; (temporary)
            lda #0
            bit ob_t
            bpl +
            lda #$ff
+           sta ob_b
            clc
            lda ag_x
            adc ob_t
            sta ab_l
            lda ag_x + 1
            adc ob_b
            sta ab_l + 1
            lda ag_dy1,y
            clc
            adc ag_y
            sta ab_t
            clc                 ; the ball: x + 5 .. x + 16, y + 4 .. y + 18
            adc #18
            sta ab_b
            lda ab_t
            clc
            adc #4
            sta ab_t
            clc
            lda ab_l
            adc #16
            sta ab_r
            lda ab_l + 1
            adc #0
            sta ab_r + 1
            clc
            lda ab_l
            adc #5
            sta ab_l
            bcc +
            inc ab_l + 1
+           rts
_stand      clc                 ; standing, running: x + 6 .. x + 15, y + 2 .. y + 41
            lda ag_x
            adc #6
            sta ab_l
            lda ag_x + 1
            adc #0
            sta ab_l + 1
            clc
            lda ag_x
            adc #15
            sta ab_r
            lda ag_x + 1
            adc #0
            sta ab_r + 1
            lda ag_y
            clc
            adc #2
            sta ab_t
            adc #39
            sta ab_b
            rts

; C = 1 when the agent's box and ob_* overlap
overlap     lda ab_b            ; vertical: ab_t <= ob_b and ob_t <= ab_b
            cmp ob_t
            bcc _no
            lda ob_b
            cmp ab_t
            bcc _no
            lda ob_r            ; horizontal: ab_l <= ob_r and ob_l <= ab_r
            cmp ab_l
            lda ob_r + 1
            sbc ab_l + 1
            bcc _no
            lda ab_r
            cmp ob_l
            lda ab_r + 1
            sbc ob_l + 1
            bcc _no
            sec
            rts
_no         clc
            rts

; Once per tick in a room: does a robot or the zap touch the agent?
hit_check   lda dying
            bne _done
            jsr agent_box
            lda zap_rob
            bmi +
            jsr zap_box
            jsr overlap
            bcs die
+           ldx rb_n
            beq _done
            dex
-           lda rbx_lo,x        ; robot: x + 4 .. x + 19, y .. y + 20
            clc
            adc #4
            sta ob_l
            lda rbx_hi,x
            adc #0
            sta ob_l + 1
            lda ob_l
            clc
            adc #15
            sta ob_r
            lda ob_l + 1
            adc #0
            sta ob_r + 1
            lda rby,x
            sta ob_t
            clc
            adc #20
            sta ob_b
            stx rb_k
            jsr overlap
            bcs die
            ldx rb_k
            dex
            bpl -
_done       rts

; --- death ------------------------------------------------------------------------------
die         lda #1
            sta dying
            lda #DEATH_FLASHES
            sta death_cnt
            lda #0
            sta death_sub
            lda #$ff            ; the zap stops
            sta zap_rob
            lda $d015
            and #%11111110
            sta $d015
            ; copy the agent's three blocks, show the copies ($9720)
            ldx #2
_copy       lda M_SCREEN + $3f9,x
            sec
            sbc #AGENT_PTR0
            jsr block_addr      ; up_src = the block
            txa
            pha
            asl a               ; destination: DEATH block x
            asl a
            asl a
            asl a
            asl a
            asl a
            tax
            ldy #0
-           lda (up_src),y
            sta M_LIFTSPR,x
            inx
            iny
            cpy #64
            bne -
            pla
            tax
            clc
            adc #DEATH_PTR
            sta M_SCREEN + $3f9,x
            dex
            bpl _copy
            rts

; up_src = address of agent block A
block_addr  sta up_src + 1
            lda #0
            lsr up_src + 1
            ror a
            lsr up_src + 1
            ror a
            sta up_src
            lda up_src + 1
            clc
            adc #>M_AGENT
            sta up_src + 1
            rts

; Every frame while dying (the script and the robots wait).
death_frame lda dying
            cmp #1
            beq _flash
            cmp #2
            beq _crumble
            ; the pause, then back at the door
            dec death_cnt
            bne _done
            lda #0
            sta dying
            lda entry_x
            sta ag_x
            lda entry_x + 1
            sta ag_x + 1
            lda entry_y
            sta ag_y
            lda entry_face
            sta ag_face
            lda #FR_STAND
            sta ag_frame
            jsr robots_init
            jsr robots_draw
            jsr agent_draw
            lda death_go        ; the script goes on where C_ONDEATH said
            sta sc_p
            lda death_go + 1
            sta sc_p + 1
            jmp script_next
_done       rts
_flash      lda death_sub       ; 2 frames a flash: colours, then swapped
            eor #1
            sta death_sub
            ldx death_sub
            lda flash_body,x
            sta $d029
            sta $d02a
            lda flash_over,x
            sta $d028
            cpx #1
            bne _done
            jsr zap_crackle
            dec death_cnt
            bne _done
            lda #2
            sta dying
            lda #DEATH_ROUNDS
            sta death_cnt
            rts
_crumble    lda death_sub
            eor #1
            sta death_sub
            beq _done
            jsr zap_crackle
            ldy #48             ; 49 random pixels off each of the 3 blocks ($97d7)
_px         jsr rnd_next
            and #7
            tax
            lda pixel_off,x
            sta box_tmp
            jsr rnd_next
            and #$3f
            tax
            lda M_LIFTSPR,x
            and box_tmp
            sta M_LIFTSPR,x
            lda M_LIFTSPR + 64,x
            and box_tmp
            sta M_LIFTSPR + 64,x
            lda M_LIFTSPR + 128,x
            and box_tmp
            sta M_LIFTSPR + 128,x
            dey
            bpl _px
            dec death_cnt
            bne _done
            ldx #191            ; gone
            lda #0
-           sta M_LIFTSPR,x
            dex
            cpx #$ff
            bne -
            jsr zap_quiet
            lda #1              ; the agent's colours back for later
            sta $d028
            lda #11
            sta $d029
            sta $d02a
            lda #3
            sta dying
            lda #DEATH_PAUSE
            sta death_cnt
            rts

flash_body  .byte $01, $0f      ; the original's $9783 / $9785
flash_over  .byte $0b, $0c
pixel_off   .byte $fe, $fd, $fb, $f7, $ef, $df, $bf, $7f
rbcool      .fill 4
