;=======================================
;Config file (presets + settings) : config.i
;=======================================

;Point the Application file reference at "config.i".
;appfileref ($0338) holds a page-aligned pointer to the
;bundle FileRef; write the name into its frefname field.
setcfgnm
        .block
        lda appfileref
        clc
        adc #frefname
        sta $fb
        lda appfileref+1
        adc #0
        sta $fc
        ldy #0
lp      lda s_cfgnm,y
        sta ($fb),y
        beq done
        iny
        cpy #17
        bcc lp
done    rts
        .bend

;Zero the whole preset table and deselect.
presclr
        .block
        ldx #0
        lda #0
clr     sta presets,x
        inx
        cpx #(NPRESET*prsize)
        bcc clr
        lda #$ff
        sta st_psel
        rts
        .bend

;Load config.i over the defaults. Missing file -> keep
;defaults; wrong version/layout -> reset presets.
loadcfg
        .block
        jsr setcfgnm
        #rdxy appfileref
        lda #ff_r
        jsr fopen
        bcs none          ;not found -> defaults
        jsr fread
        .word cfgblk
        .word cfgsize
        jsr fclose
        lda cfgvers       ;validate format
        cmp #cfg_ver
        bne bad
        lda cfgnpre
        cmp #NPRESET
        bne bad
        lda cfgpsz
        cmp #prsize
        bne bad
        rts
bad     jsr presclr
none    rts
        .bend

;Write the config block to config.i (create/overwrite).
savecfg
        .block
        lda #cfg_ver      ;refresh header before writing
        sta cfgvers
        lda #NPRESET
        sta cfgnpre
        lda #prsize
        sta cfgpsz
        jsr setcfgnm
        #rdxy appfileref
        lda #(ff_w|ff_o)
        jsr fopen
        bcs none
        jsr fwrite
        .word cfgblk
        .word cfgsize
        jsr fclose
none    rts
        .bend

