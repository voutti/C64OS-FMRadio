;=======================================
;RDA5807 control (via i2c.lib)
;=======================================

;--- chip identity ---
radioadr = $11     ;RDA5807 random-access i2c addr (7-bit)
chipidrg = $00     ;chip-id register
chipidvl = $58     ;expected RDA5807 chip id

;--- RDA5807 registers & bit masks ---
rd_ctrl  = $02
rd_chan  = $03
rd_iocfg = $04
rd_vol   = $05
rd_seek  = $0a     ;seek/RDS status reg
rd_stat  = $0b     ;RSSI/status reg (RSSI in bits15:9)
m_dhiz   = $80
m_dmute  = $40
m_mono   = $20
m_bass   = $10
m_seekup = $02
m_seek   = $01
m_enable = $01
m_rds    = $08
m_tune   = $10
m_deemph = $08
m_voldac = $0f
m_stc    = $40     ;seek/tune complete (status hi byte)
m_st     = $04     ;stereo indicator (reg 0x0A bit10, hi byte)
m_lnap   = $c0     ;LNA antenna-port mask (reg 0x05 lo)
lna_port = $c0     ;$80 = LNAP input (RDA5807 reset default), $40 = LNAN, $c0 = DUAL (both inputs — often best)
vol_max  = $0f
rssi_flr = 15      ;RSSI noise floor (bar empty at/below this)
rssi_top = 63      ;RSSI at full bar (useful window = flr..top)
frq_min  = 870     ;87.0 MHz (100kHz units)
frq_max  = 1080    ;108.0 MHz

;Record the last I2C comms result for the host app to
;surface however it likes (no UI dependency here).
;i2cok -> 0 (ok), i2cbad -> 1 (comms error).
i2cok   lda #0
        sta i2cres
        rts
i2cbad  lda #1
        sta i2cres
        rts

;Read-modify-write a 16-bit RDA register.
;Caller sets updreg,updmh,updml,updvh,updvl.
i2cupdate
        .block
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy updreg
        clc
        jsr i2creadrg
        bne cerr
        lda updmh
        eor #$ff
        and i2cbuf
        sta updtmp
        lda updvh
        and updmh
        ora updtmp
        sta i2cbuf
        lda updml
        eor #$ff
        and i2cbuf+1
        sta updtmp
        lda updvl
        and updml
        ora updtmp
        sta i2cbuf+1
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy updreg
        jsr i2cwritrg
.if DEBUG
        jsr dbgwrite
.endif
        jsr i2cok
        rts
cerr    jsr i2cbad
        rts
        .bend

.if DEBUG
;Temporary debug: show the last register write in
;the status label as "0xYY = 0xZZZZ" (YY=register,
;ZZZZ=16-bit value written). Set DEBUG=0 to remove.
dbgwrite
        .block
        ldx #0
        lda #"0"
        sta dbgstr,x
        inx
        lda #"x"
        sta dbgstr,x
        inx
        lda updreg
        jsr putbyte
        lda #" "
        sta dbgstr,x
        inx
        lda #"="
        sta dbgstr,x
        inx
        lda #" "
        sta dbgstr,x
        inx
        lda #"0"
        sta dbgstr,x
        inx
        lda #"x"
        sta dbgstr,x
        inx
        lda i2cbuf        ;value hi byte
        jsr putbyte
        lda i2cbuf+1      ;value lo byte
        jsr putbyte
        lda #0
        sta dbgstr,x
        #copy16 dbgstr,mktp
        jmp setstat
        .bend

;A -> byte, X -> dbgstr index. Emits two hex
;digits at dbgstr,x and advances X by 2.
putbyte
        .block
        pha
        lsr
        lsr
        lsr
        lsr
        jsr nib
        pla
        and #$0f
nib     cmp #10
        bcc dig
        sec
        sbc #10
        clc
        adc #"A"
        bne sto
dig     ora #"0"
sto     sta dbgstr,x
        inx
        rts
        .bend
.endif

;Power on/off (st_pwr).
r_power
        .block
        lda #rd_ctrl
        sta updreg
        lda #m_dhiz
        sta updmh
        sta updvh
        lda #(m_enable|m_rds)
        sta updml
        ldx st_pwr
        beq off
        lda #(m_enable|m_rds)
        bne set
off     lda #0
set     sta updvl
        jsr i2cupdate
        lda st_pwr
        beq done
        lda #rd_chan
        sta updreg
        lda #0
        sta updmh
        sta updvh
        lda #m_tune
        sta updml
        sta updvl
        jsr i2cupdate
done    rts
        .bend

;Mute (st_mute 1=muted). DMUTE=1 means NOT muted.
r_mute
        .block
        lda #rd_ctrl
        sta updreg
        lda #m_dmute
        sta updmh
        lda #0
        sta updml
        sta updvl
        ldx st_mute
        bne on
        lda #m_dmute
        bne set
on      lda #0
set     sta updvh
        jmp i2cupdate
        .bend

;Bass boost (st_bass).
r_bass
        .block
        lda #rd_ctrl
        sta updreg
        lda #m_bass
        sta updmh
        lda #0
        sta updml
        sta updvl
        ldx st_bass
        beq off
        lda #m_bass
        bne set
off     lda #0
set     sta updvh
        jmp i2cupdate
        .bend

;Stereo/mono (st_ster 0=stereo,1=mono).
r_stereo
        .block
        lda #rd_ctrl
        sta updreg
        lda #m_mono
        sta updmh
        lda #0
        sta updml
        sta updvl
        ldx st_ster
        beq st
        lda #m_mono
        bne set
st      lda #0
set     sta updvh
        jmp i2cupdate
        .bend

;De-emphasis (st_deem 0=50us,1=75us). DEEMPH set = 50us.
r_deem
        .block
        lda #rd_iocfg
        sta updreg
        lda #m_deemph
        sta updmh
        lda #0
        sta updml
        sta updvl
        ldx st_deem
        bne d75
        lda #m_deemph
        bne set
d75     lda #0
set     sta updvh
        jmp i2cupdate
        .bend

;Volume (st_vol 0..15) + LNA antenna port.
;LNA_PORT is written explicitly (not just left at
;the reset default) so reception is correct even if
;the read-modify-write can't read reg 0x05 back.
r_vol
        .block
        lda #rd_vol
        sta updreg
        lda #0
        sta updmh
        sta updvh
        lda #(m_voldac|m_lnap)
        sta updml
        lda st_vol
        and #m_voldac
        ora #lna_port
        sta updvl
        jmp i2cupdate
        .bend

;Set frequency from st_freq. 100kHz spacing:
;CHAN=freq-870 goes to reg 0x03 bits 15:6, with
;SPACE=00 (100kHz) and TUNE=1.
r_freq
        .block
        lda st_freq
        sec
        sbc #<frq_min
        sta updtmp        ;d = channel (100kHz steps, 0..210)
        lda #rd_chan
        sta updreg
        lda #$ff
        sta updmh
        lda #$d3          ;mask: CHANlo|TUNE|SPACE
        sta updml
        lda updtmp        ;CHAN<<6 -> updvh:updvl
        sta updvl
        lda #0
        sta updvh
        ldx #6
shl6    asl updvl
        rol updvh
        dex
        bne shl6
        lda updvl
        ora #m_tune       ;TUNE=1, SPACE=00 (100kHz)
        sta updvl
        jmp i2cupdate
        .bend

;Start scan. A=1 up, A=0 down.
;Clear SEEK first so there is a fresh 0->1 edge
;(this also clears a stale STC), then set the
;direction + SEEK to start the new seek.
r_scan
        .block
        pha
        lda #rd_ctrl
        sta updreg
        lda #m_seek
        sta updmh
        lda #0
        sta updml
        sta updvl
        sta updvh         ;SEEK=0
        jsr i2cupdate
        lda #rd_ctrl
        sta updreg
        lda #(m_seekup|m_seek)
        sta updmh
        lda #0
        sta updml
        sta updvl
        pla
        asl               ;dir<<1 (SEEKUP)
        ora #m_seek       ;SEEK=1
        sta updvh
        jmp i2cupdate
        .bend

;Read the tuned frequency from the chip into
;st_freq.  chan = reg3>>6;  freq = 870+chan.
r_getfreq
        .block
        lda #0
        sta frqbad
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy #rd_chan
        clc
        jsr i2creadrg
        bne fail          ;no ack -> keep model value
        lda i2cbuf
        sta gfhi
        lda i2cbuf+1
        sta gflo
        ldx #6
sh      lsr gfhi
        ror gflo
        dex
        bne sh
        lda gflo
        clc
        adc #<frq_min
        sta st_freq
        lda gfhi
        adc #>frq_min
        sta st_freq+1
        ;chip can report an out-of-band channel before it
        ;is powered/initialized -> fall back to frq_min
        lda st_freq+1
        cmp #>frq_min
        bcc clamp
        bne chkmax
        lda st_freq
        cmp #<frq_min
        bcc clamp
chkmax  lda #>frq_max
        cmp st_freq+1
        bcc clamp
        bne fail
        lda #<frq_max
        cmp st_freq
        bcc clamp
        bcs fail
clamp   #copy16 frq_min,st_freq
        lda #1
        sta frqbad        ;chip clearly not configured yet
fail    rts
        .bend

;Read RSSI (0..127) from status reg 0x0b.
r_rssi
        .block
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy #rd_stat
        clc
        jsr i2creadrg
        bne fail          ;no ack -> keep previous
        lda i2cbuf        ;bits15:8; RSSI in bits15:9
        lsr               ;-> RSSI[6:0]
        sta st_rssi
        jmp i2cok
fail    jmp i2cbad
        .bend

;Read stereo indicator (reg 0x0A bit10) into st_stind.
r_stind
        .block
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy #rd_seek
        clc
        jsr i2creadrg
        bne fail
        lda i2cbuf        ;hi byte; ST(bit10) -> hi bit2
        and #m_st
        jsr bit01
        sta st_stind
fail    rts
        .bend

;Read current control/config from the chip into the
;state model so the UI reflects the actual settings.
;reg 0x02: hi=DHIZ/DMUTE/MONO/BASS, lo=ENABLE.
;reg 0x04: hi=DEEMPH.  reg 0x05: lo=VOLUME.
readstate
        .block
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy #rd_ctrl
        clc
        jsr i2creadrg
        bne fail
        lda i2cbuf
        sta gfhi          ;control hi byte
        lda i2cbuf+1
        sta gflo          ;control lo byte
        lda gfhi
        and #m_mono
        jsr bit01
        sta st_ster       ;MONO set -> mono
        lda gfhi
        and #m_bass
        jsr bit01
        sta st_bass
        lda gfhi
        and #m_dmute
        jsr bit01
        eor #1            ;DMUTE set = NOT muted
        sta st_mute
        lda gflo
        and #m_enable
        jsr bit01
        sta st_pwr
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy #rd_iocfg
        clc
        jsr i2creadrg
        bne fail
        lda i2cbuf
        and #m_deemph
        jsr bit01
        eor #1            ;DEEMPH set = 50us -> st_deem 0
        sta st_deem
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy #rd_vol
        clc
        jsr i2creadrg
        bne fail
        lda i2cbuf+1
        and #m_voldac
        sta st_vol
fail    rts
        .bend

;A=masked bits -> A=0 (clear) or 1 (any set).
bit01
        .block
        beq z
        lda #1
z       rts
        .bend

;Poll the seek/tune-complete bit (with timeout).
;Delay before each read so a stale STC from a
;previous seek isn't mistaken for this one.
r_scanwait
        .block
        lda #30
        sta swto
loop    jsr rdelay
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy #rd_seek
        clc
        jsr i2creadrg
        bne done          ;no ack -> stop (no hardware)
        lda i2cbuf
        and #m_stc
        bne done          ;complete
        dec swto
        bne loop
done    rts
        .bend

;Push all current settings to the chip.
applyall
        jsr r_freq
        jsr r_vol
        jsr r_stereo
        jsr r_bass
        jsr r_deem
        jmp r_mute

