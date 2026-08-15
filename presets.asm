;=======================================
;Presets
;=======================================

;A=slot -> stmp = presets + slot*19 (offset < 256).
precptr
        .block
        sta ptmp          ;slot
        asl
        sta ptmp2         ;slot*2
        asl
        asl
        asl               ;slot*16
        clc
        adc ptmp2         ;+slot*2 = slot*18
        clc
        adc ptmp          ;+slot   = slot*19
        clc
        adc #<presets
        sta stmp
        lda #>presets
        adc #0
        sta stmp+1
        rts
        .bend

;-> A = first free (used=0) slot, or $ff if none.
pfree
        .block
        lda #0
        sta pidx
loop    lda pidx
        jsr precptr
        #rdxy stmp
        jsr ptrthis
        ldy #0
        lda (this),y
        beq found
        inc pidx
        lda pidx
        cmp #NPRESET
        bcc loop
        lda #$ff
        rts
found   lda pidx
        rts
        .bend

;Scan presets for one whose stored frequency == st_freq.
;Match -> select that slot; no match -> deselect. Only
;refreshes the radios when the selection actually changes.
psync
        .block
        lda #0
        sta pidx
loop    lda pidx
        jsr precptr
        #rdxy stmp
        jsr ptrthis
        ldy #0
        lda (this),y      ;used?
        beq nxt
        ldy #1
        lda (this),y
        cmp st_freq
        bne nxt
        ldy #2
        lda (this),y
        cmp st_freq+1
        bne nxt
        lda pidx          ;match
        jmp setsel
nxt     inc pidx
        lda pidx
        cmp #NPRESET
        bcc loop
        lda #$ff           ;no match
setsel  cmp st_psel
        beq done           ;unchanged -> no redraw
        sta st_psel
        jsr updpres
done    rts
        .bend

;A=slot -> if used, tune to its stored frequency.
ptune
        .block
        jsr precptr
        #rdxy stmp
        jsr ptrthis
        ldy #0
        lda (this),y
        beq done          ;empty slot -> ignore
        ldy #1
        lda (this),y
        sta st_freq
        iny
        lda (this),y
        sta st_freq+1
        jsr r_freq
        jsr updui
done    rts
        .bend

;Refresh all preset name+freq labels (name labels point at
;the record name fields; freq strings are formatted here) and
;the radio selection states.
updpres
        .block
        lda #0
        sta pidx
loop    lda pidx          ;format this slot's frequency string
        jsr pfmt
        lda pidx          ;mark name label dirty
        asl
        tay
        lda pnamlbl,y
        sta stmp
        lda pnamlbl+1,y
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        #setflag this,dflags,df_dirty
        lda pidx          ;mark freq label dirty
        asl
        tay
        lda pfrqlbl,y
        sta stmp
        lda pfrqlbl+1,y
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        #setflag this,dflags,df_dirty
        lda pidx          ;radio cf_state = (slot==st_psel)
        asl
        tay
        lda pradbtn,y
        sta stmp
        lda pradbtn+1,y
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        ldy #cflags
        lda (this),y
        and #(255-cf_state)
        ldx pidx
        cpx st_psel
        bne wr
        ora #cf_state
wr      sta (this),y
        #setflag this,dflags,df_dirty
        inc pidx
        lda pidx
        cmp #NPRESET
        bcs done
        jmp loop
done    rts
        .bend

;A=slot -> format its stored frequency into pfrqstr[slot],
;or blank the string when the slot is unused.
pfmt
        .block
        jsr precptr        ;stmp -> record, ptmp = slot
        lda ptmp
        asl
        asl
        asl                ;slot*8
        clc
        adc ptmp           ;slot*9
        sta pfbase
        #rdxy stmp
        jsr ptrthis
        ldy #0
        lda (this),y       ;used?
        beq blank
        ldy #1
        lda (this),y
        sta dlo
        iny
        lda (this),y
        sta dhi
        jsr freqfmtd       ;-> freqstr (8 chars + null)
        ldx pfbase
        ldy #0
cp      lda freqstr,y
        sta pfrqstr,x
        beq done
        inx
        iny
        cpy #9
        bcc cp
        rts
blank   ldx pfbase         ;8 spaces so the label clears on
        ldy #8             ;redraw, then null terminator
        lda #$20
bl      sta pfrqstr,x
        inx
        dey
        bne bl
        lda #0
        sta pfrqstr,x
done    rts
        .bend

;Build 8 preset rows (blue name label + radio) at
;rows 14..21, then link the radios into one group.
buildpres
        .block
        lda #0
        sta pidx
loop    lda pidx          ;radio on the left
        jsr precptr
        lda #bt_rad
        sta mkbt
        #copy16 s_empty,mktp
        #copy16 a_preset,mktg
        lda #3
        sta mkw
        lda pidx
        clc
        adc #15           ;row = 15 + slot
        ldx #2
        jsr mkbtn
        #rdxy mkobj        ;tag = slot index
        jsr ptrthis
        lda pidx
        ldy #tag
        sta (this),y
        lda pidx
        asl
        tay
        lda mkobj
        sta pradbtn,y
        lda mkobj+1
        sta pradbtn+1,y
        lda pidx          ;name label -> record name field
        jsr precptr
        lda stmp
        clc
        adc #3
        sta mktp
        lda stmp+1
        adc #0
        sta mktp+1
        lda #16
        sta mkw
        lda #0
        sta mkflg
        lda pidx
        clc
        adc #15
        ldx #6
        jsr mklbl
        #rdxy mkobj        ;blue name colour
        jsr ptrthis
        lda #cblue
        ldy #bcolor
        sta (this),y
        lda pidx
        asl
        tay
        lda mkobj
        sta pnamlbl,y
        lda mkobj+1
        sta pnamlbl+1,y
        lda pidx          ;freq label -> pfrqstr[slot], x23 w8
        asl
        asl
        asl
        clc
        adc pidx          ;slot*9
        clc
        adc #<pfrqstr
        sta mktp
        lda #>pfrqstr
        adc #0
        sta mktp+1
        lda #8
        sta mkw
        lda #0
        sta mkflg
        lda pidx
        clc
        adc #15
        ldx #23
        jsr mklbl
        #rdxy mkobj        ;blue like the name
        jsr ptrthis
        lda #cblue
        ldy #bcolor
        sta (this),y
        lda pidx
        asl
        tay
        lda mkobj
        sta pfrqlbl,y
        lda mkobj+1
        sta pfrqlbl+1,y
        inc pidx
        lda pidx
        cmp #NPRESET
        bcs pbdone
        jmp loop
pbdone  jsr linkpres
        rts
        .bend

;Chain the 8 preset radios into one bnext ring so they
;behave as a single mutually-exclusive group.
linkpres
        .block
        lda #0
        sta pidx
loop    lda pidx
        asl
        tay
        lda pradbtn,y
        sta stmp
        lda pradbtn+1,y
        sta stmp+1
        lda pidx           ;next index (wrap)
        clc
        adc #1
        cmp #NPRESET
        bcc nn
        lda #0
nn      asl
        tay
        lda pradbtn,y
        sta ptmp
        lda pradbtn+1,y
        sta ptmp2
        #rdxy stmp
        jsr ptrthis
        ldy #bnext
        lda ptmp
        sta (this),y
        iny
        lda ptmp2
        sta (this),y
        inc pidx
        lda pidx
        cmp #NPRESET
        bcc loop
        rts
        .bend

;Reset the name field to empty. For a TKInput, re-init
;its length/index via setstr_; for the fallback label
;just mark it dirty.
nameclr
        .block
        lda #0
        sta namebuf        ;empty string
        lda widgets+w_name*2
        sta stmp
        lda widgets+w_name*2+1
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        lda tkincls
        ora tkincls+1
        beq lblonly
        ldy #setstr_
        jsr getmethod
        ldx #<namebuf
        ldy #>namebuf
        lda #pnamlen
        jsr sysjmp
lblonly #setflag this,dflags,df_dirty
        rts
        .bend

