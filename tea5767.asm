;=======================================
;TEA5767 control (via i2c.lib)
;=======================================

radioadr = $60     ;TEA5767 compatible-mode i2c addr (7-bit)
frq_min  = 870     ;87.0 MHz (100kHz units)
frq_max  = 1080    ;108.0 MHz
vol_max  = $0f     ;UI compatibility (chip has no volume DAC)
rssi_flr = 15      ;keep UI RSSI scaling constants aligned
rssi_top = 63
use_stby = 0       ;0 = mute-only soft off (more reliable on clone modules)

;Write/read mode bit masks.
m_mute    = $80
m_search  = $40
m_stup    = $80
m_mono    = $08
m_hilo    = $10
m_srchlv  = $60
m_stby    = $40
m_xtal32k = $10
m_soft    = $08
m_hicut   = $04
m_stn     = $02
m_de75    = $40
m_ready   = $80
m_st      = $80

;Divider approximation constants for 32.768kHz + high-LO mode.
;Exact integer model for N=floor((f*400000+900000)/32768), f in 100kHz.
;At f=870: N=10647 ($2997), rem=19104 ($4aa0), step num=6784 ($1a80).
div_bhi = $29
div_blo = $97
rem_bhi = $4a
rem_blo = $a0
rem_shi = $1a
rem_slo = $80

;Record the last I2C comms result for the host app.
i2cok   lda #0
        sta i2cres
        rts
i2cbad  lda #1
        sta i2cres
        rts

;Read 5 TEA status bytes into i2cbuf[0..4].
t_read5
        .block
        #ldxy i2cbuf
        lda #5
        jsr i2cpreprw
        lda #radioadr
        ldy #0
        sec               ;skip register write, pure sequential read
        jsr i2creadrg
        bne fail
        jmp i2cok
fail    jmp i2cbad
        .bend

;Write TEA control bytes tw0..tw4.
;writreg sends Y first, then the prep_rw buffer bytes.
t_write5
        .block
        lda tw1
        sta i2cbuf
        lda tw2
        sta i2cbuf+1
        lda tw3
        sta i2cbuf+2
        lda tw4
        sta i2cbuf+3
        #ldxy i2cbuf
        lda #4
        jsr i2cpreprw
        lda #radioadr
        ldy tw0
        jsr i2cwritrg
        bne fail
        jmp i2cok
fail    jmp i2cbad
        .bend

;Compute divider (divhi:divlo) from st_freq using a fixed-point
;exact step model derived from the TEA5767 PLL equation.
t_freq2div
        .block
        lda st_freq
        sec
        sbc #<frq_min
        sta updtmp         ;delta steps (0..210)
        lda #div_bhi
        sta divhi
        lda #div_blo
        sta divlo
        lda #rem_bhi
        sta rdvhi
        lda #rem_blo
        sta rdvlo
lp      lda updtmp
        beq done
        ;divider += 12
        lda divlo
        clc
        adc #12
        sta divlo
        bcc radd
        inc divhi
radd    ;rem += 6784; if rem >= 32768 then rem -= 32768 and divider += 1
        lda rdvlo
        clc
        adc #rem_slo
        sta rdvlo
        lda rdvhi
        adc #rem_shi
        sta rdvhi
        cmp #$80
        bcc ninc
        lda rdvlo
        sec
        sbc #$00
        sta rdvlo
        lda rdvhi
        sbc #$80
        sta rdvhi
        inc divlo
        bne ninc
        inc divhi
ninc    dec updtmp
        jmp lp
done    rts
        .bend

;Build tw0..tw4 from the state model + divider shadow.
t_build
        .block
        jsr t_freq2div

        ;byte2 defaults: high-LO injection, optional mono.
        lda #m_hilo
        sta tw2
        lda st_ster
        beq st
        lda tw2
        ora #m_mono
        sta tw2
st
        ;byte3 defaults: 32k crystal + soft-mute/high-cut/st-noise.
        lda #(m_xtal32k|m_soft|m_hicut|m_stn)
        sta tw3
        lda st_pwr
        bne pwr
        lda #use_stby
        beq pwr
        lda tw3
        ora #m_stby
        sta tw3
pwr
        ;byte4: deemphasis (75us bit set).
        lda #0
        sta tw4
        lda st_deem
        beq d50
        lda #m_de75
        sta tw4
d50
        ;byte0/1: divider + mute/search bits.
        lda divhi
        and #$3f
        sta tw0
        lda divlo
        sta tw1
        lda st_mute
        bne dom
        lda st_pwr
        bne nom
dom     lda tw0
        ora #m_mute
        sta tw0
        bne nom
nom
        lda tscan
        beq nos
        lda tw0
        ora #(m_search|m_mute)
        sta tw0
        lda tw2
        ora #m_srchlv
        sta tw2
        lda tscan
        cmp #2
        bne nos
        lda tw2
        ora #m_stup
        sta tw2
nos
        lda #0
        sta tscan         ;search direction is one-shot, like ctrl.search in C version
        rts
        .bend

;Probe heuristic: read 5 bytes, require a valid chip-id nibble
;in status byte4 (low nibble should be zero on TEA5767).
;C clear = looks supported.
r_probe
        .block
        jsr t_read5
        lda i2cres
        bne fail
        lda i2cbuf+3
        and #$0f
        bne fail
        clc
        rts
fail    sec
        rts
        .bend

;Power on/off (st_pwr).
r_power
        .block
        lda st_pwr
        bne on
        jsr t_build
        jmp t_write5
on      jsr i2creset      ;some TEA5767 modules need a fresh bus phase after standby
        jsr rdelay
        jsr t_build
        jsr t_write5
        jsr rdelay        ;second write improves wake reliability on clone boards
        jsr t_build
        jmp t_write5
        .bend

;Mute (st_mute 1=muted).
r_mute
        .block
        jsr t_build
        jmp t_write5
        .bend

;Bass boost unsupported on TEA5767.
r_bass
        lda #0
        sta st_bass
        rts

;Stereo/mono (st_ster 0=stereo,1=mono).
r_stereo
        .block
        jsr t_build
        jmp t_write5
        .bend

;De-emphasis (st_deem 0=50us,1=75us).
r_deem
        .block
        jsr t_build
        jmp t_write5
        .bend

;Volume unsupported on TEA5767 (keep UI compatibility state).
r_vol
        lda #vol_max
        sta st_vol
        rts

;Set frequency from st_freq.
r_freq
        .block
        jsr t_build
        jmp t_write5
        .bend

;Start scan. A=1 up, A=0 down.
;Nudge the start channel so a scan can advance from edge channels.
r_scan
        .block
        cmp #0
        beq dn
        lda #2
        sta tscan
        lda st_freq
        cmp #<frq_max
        bne incf
        lda st_freq+1
        cmp #>frq_max
        bne incf
        #copy16 frq_min,st_freq
        bne go
incf    inc st_freq
        bne go
        inc st_freq+1
        bne go
dn      lda #1
        sta tscan
        lda st_freq
        cmp #<frq_min
        bne decf
        lda st_freq+1
        cmp #>frq_min
        bne decf
        #copy16 frq_max,st_freq
        bne go
decf    lda st_freq
        bne d0
        dec st_freq+1
d0      dec st_freq
go      jsr t_build
        jmp t_write5
        .bend

;Poll READY bit after seek/tune.
r_scanwait
        .block
        lda #40
        sta swto
lp      jsr rdelay
        jsr t_read5
        lda i2cres
        bne done
        lda i2cbuf
        and #m_ready
        bne done
        dec swto
        bne lp
done    rts
        .bend

;Read tuned frequency into st_freq.
;Uses the same divider approximation by scanning 87.0..108.0
;until the model divider reaches the chip divider.
r_getfreq
        .block
        lda #0
        sta frqbad
        jsr t_read5
        lda i2cres
        bne fail
        lda i2cbuf
        and #$3f
        sta rdvhi
        lda i2cbuf+1
        sta rdvlo
        #copy16 frq_min,st_freq
nxt     jsr t_freq2div
        lda divhi
        cmp rdvhi
        bcc finc
        bne done
        lda divlo
        cmp rdvlo
        bcs done
finc    lda st_freq
        cmp #<frq_max
        bne add
        lda st_freq+1
        cmp #>frq_max
        beq done
add     inc st_freq
        bne nxt
        inc st_freq+1
        jmp nxt
done    rts
fail    lda #1
        sta frqbad
        rts
        .bend

;Read RSSI/station-ready into model.
r_rssi
        .block
        jsr t_read5
        lda i2cres
        bne done
        lda i2cbuf+3
        and #$f0
        lsr
        lsr               ;0..60 (4-step granularity)
        sta st_rssi
        lda i2cbuf
        and #m_ready
        jsr bit01
        sta st_fmtr
done    rts
        .bend

;Read stereo indicator into st_stind.
r_stind
        .block
        jsr t_read5
        lda i2cres
        bne done
        lda i2cbuf+2
        and #m_st
        jsr bit01
        sta st_stind
done    rts
        .bend

;TEA readback does not expose all control bits in a direct
;RDA-like way, so keep unsupported controls pinned to defaults.
readstate
        lda #0
        sta st_bass
        lda #vol_max
        sta st_vol
        rts

;A=masked bits -> A=0 (clear) or 1 (any set).
bit01
        .block
        beq z
        lda #1
z       rts
        .bend

;Push current settings to the chip.
applyall
        jsr r_freq
        jsr r_stereo
        jsr r_bass
        jsr r_deem
        jmp r_mute
