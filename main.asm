;----[ main.a - FM-Radio ]-----------

        .include "os/h/modules.h"

        ;Useful Constants/Macros

        #inc_s "app"
        #inc_s "colors"
        #inc_s "ctxdraw"
        #inc_s "io"
        ;These define \1..\9 macros; the inc_ wrapper (.segment) would capture those params, so include directly.
        .include "os/s/pointer.s"
        .include "os/s/switch.s"

        ;Kernal Module Constants

        #inc_s "screen"
        #inc_s "service"
        #inc_s "toolkit"
        #inc_s "memory"
        #inc_s "timers"

        #inc_tks "tksizes"
        #inc_tks "tkview"
        #inc_tks "tkctrl"
        #inc_tks "tkbutton"
        #inc_tks "tklabel"

        #inc_tkh "tkview"
        #inc_tkh "tkctrl"
        #inc_tkh "tkbutton"
        #inc_tkh "tklabel"
        #inc_tkh "classes"
        #inc_tkh "tkobj"

;---------------------------------------
;RDA5807 FM tuner via C64 OS i2c.lib.r
;Load id bytes are the PETSCII filename
;chars "I2" (on disk: I2C.LIB.R); 3 pages.
i2cpages = 3
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
m_lnap   = $c0     ;LNA antenna-port mask (reg 0x05 lo)
lna_port = $c0     ;$80 = LNAP input (RDA5807 reset default), $40 = LNAN, $c0 = DUAL (both inputs — often best)
vol_max  = $0f
frq_min  = 870     ;87.0 MHz (100kHz units)
frq_max  = 1080    ;108.0 MHz
c_on     = cgreen  ;toggle button on colour
c_off    = cdgrey  ;toggle button off colour

;--- debug ---
DEBUG    = 1       ;1 = log each i2c register write in the status label; set 0 to remove

;custom async message code (timer trigger -> msgcmd)
mc_rssi  = $80

;--- widget store indices ---
w_freq = 0
w_stat = 1
w_pwr  = 2
w_ster = 3
w_bass = 4
w_mute = 5
w_deem = 6
w_volu = 7
w_vold = 8
w_scnu = 9
w_scnd = 10
w_fmu  = 11
w_fmd  = 12
w_fku  = 13
w_fkd  = 14

;---------------------------------------
;Data Structures

         * = appbase

; application jump table
         .word init     ;App Initializer
         .word msgcmd   ;Message Handler
         .word willquit ;App Clean Up
         .word raw_rts  ;REU Freeze (raw_rts for dummy no action)
         .word raw_rts  ;REU Thaw (raw_rts for dummy no action)

; ------------------------------------
; screen layer 
layer    .word l_update
         .word l_mouse ;MouseEvt Handler (sec_rts for dummy no action)
         .word l_cmd   ;Kcmd Evt Handler (sec_rts for dummy no action)
         .word l_prnt  ;KprntEvt handler (sec_rts for dummy no action)
         .byte 0       ;Layer Index

; ------------------------------------
; draw context
drawctx  .word scrbuf      ;Char Origin
         .word colbuf      ;Colr Origin
         .byte screen_cols ;Buff Width
         .byte screen_cols ;Draw Width
         .byte screen_rows ;Draw Height
         .word 0           ;Offset Top
         .word 0           ;Offset Left

tkenv
        .word drawctx ;draw contex
        .byte 0       ;memory pool
        .byte 1       ;dirty
        .byte 0       ;scrlayer 0
        .word 0       ;root view
        .word 0       ;1st key view
        .word 0       ;1st mus view
        .word 0       ;clikmus view
        .byte 0       ;ctx2scr ppsx
        .byte 0       ;ctx2scr posy

strcolor .byte clblue

;--- radio state model (defaults) ---
st_pwr   .byte 0       ;power 0/1
st_ster  .byte 0       ;0=stereo 1=mono
st_bass  .byte 0       ;bass 0/1
st_mute  .byte 0       ;mute 0/1
st_deem  .byte 0       ;0=50us 1=75us
st_vol   .byte $0a     ;volume 0..15
st_freq  .word 1000    ;100kHz units -> 100.0 MHz
st_rssi  .byte 0       ;last RSSI 0..127

;--- widget pointer store (w_* indices) ---
widgets  .word 0,0,0,0,0,0,0,0
         .word 0,0,0,0,0,0,0

;--- i2c buffer + scratch ---
i2cbuf   .byte 0,0,0,0
radiomsg .word msg_probe   ;probe result, shown in status label
updreg   .byte 0
updmh    .byte 0
updml    .byte 0
updvh    .byte 0
updvl    .byte 0
updtmp   .byte 0
stmp     .word 0
mktop    .byte 0
mkleft   .byte 0
mkw      .byte 0
mkflg    .byte 0
mkobj    .word 0
mktp     .word 0
mktg     .word 0
dlo      .byte 0
dhi      .byte 0
whole    .byte 0
frac     .byte 0
rtry     .byte 0
gfhi     .byte 0
gflo     .byte 0
swto     .byte 0
blev     .byte 0
bidx     .byte 0
bofs     .byte 0
bcol     .byte 0
btmp     .byte 0
brow     .byte 0
rssireq  .byte 0       ;set by timer, serviced in l_update
freqstr  .byte 0,0,0,0,0,0,0,0,0,0,0,0
.if DEBUG
dbgstr   .fill 20,0
.endif

;bar cell label pointers: [0..7]=volume, [8..15]=rssi
barcells .word 0,0,0,0,0,0,0,0
         .word 0,0,0,0,0,0,0,0

;~2-second RSSI poll timer struct
tmr      .byte 0,0,0              ;ttime countdown
         .byte (tintrvl|tcancel)  ;tstat: interval + initial reset
         .word tmrtick            ;ttrig
         .byte 120,0,0            ;tvalu reset (~2s @ 60Hz)

;--- strings ---
msg_probe .null "Probing RDA5807..."
msg_noi2c .null "I2C library missing"
msg_nordo .null "RDA5807 not found"
msg_rdyok .null "RDA5807 detected"

s_pwron  .null "Power On"
s_pwrof  .null "Power Off"
s_stereo .null "Stereo"
s_mono   .null "Mono"
s_bason  .null "Bass On"
s_basof  .null "Bass Off"
s_mton   .null "Mute On"
s_mtof   .null "Mute Off"
s_deem50 .null "Emph 50us"
s_deem75 .null "Emph 75us"
s_volup  .null "Vol +"
s_voldn  .null "Vol -"
s_scnup  .null "Scan >>"
s_scndn  .null "Scan <<"
s_fmup   .null "++"
s_fmdn   .null "--"
s_fkup   .null "+"
s_fkdn   .null "-"
s_lvol   .null "Vol"
s_lrss   .null "Rss"
s_cell   .byte $20,0        ;1-char bar cell (reversed = solid block)

;---------------------------------------

init
         .block
        ; Comment this for final build! - This is just for calculating
        ; amount of 256b pages needed. Note, every tk obj requires additional 3 bytes.
.comment
        tktotsz = tkviewsz + tkctrlsz + tkctrlsz + (3 * 3); TODO !
        .warn "tktotsz = ", tktotsz
        npages = (tktotsz + 256 - 1) / 256
        .warn "npages = ", npages
.endcomment

        #ldxy externs
        jsr initextern

        ;Load i2c.lib and probe the RDA5807
        jsr radioinit

        ;If the chip was detected, sync st_freq with
        ;its current tuning (registers survive the i2c
        ;bus reset), so the UI shows the real station.
        lda radiomsg
        cmp #<msg_rdyok
        bne nordf
        lda radiomsg+1
        cmp #>msg_rdyok
        bne nordf
        jsr r_getfreq
nordf

        ; Allocate memory for tk widgets
        lda #mapapp
        ldx #8 ;UI object pool (~33 objects)
        jsr pgalloc
        sty tkenv+te_mpool

        ;Load Shared Libraries

        ;Load Custom TK Classes
        #ldxy tkenv
        jsr settkenv

        ldx #tkview
        jsr classptr
        jsr tknew

        #stxy tkenv+te_rview

        ldy #init_
        jsr getmethod
        jsr sysjmp

        #setflag this,dflags,df_opaqu

        ;Build the radio control UI
        jsr buildui

        ;Reflect the state model on the widgets
        jsr updui

        ;If powered on (per state), push all settings
        lda st_pwr
        beq nopwr
        jsr applyall
nopwr

        ;Start the ~2s RSSI poll timer
        #ldxy tmr
        jsr timeque

        ;Push main screen layer

        #ldxy layer
        jsr layerpush

        ldx layer+slindx
        jsr markredraw

        rts
        .bend

willquit
        .block
        ;Deallocate resources here.

        ;Cancel the RSSI poll timer
        lda #tcancel
        sta tmr+tstat

        ;Unload Shared Libraries
        ldx #"i"          ;i2c.lib.r (id byte $49)
        ldy #"2"
        lda #0            ;unload flags
        jsr unldlib

        ;Unload Custom Icons

        rts
        .bend

;---------------------------------------
;Load i2c.lib, probe the RDA5807 (retrying,
;since the tuner may still be powering up)
;and pick a status message. Sets radiomsg.
radioinit
        .block
        ldx #"i"          ;i2c.lib.r load id (id byte $49)
        ldy #"2"
        lda #i2cpages     ;lo nybble = size in pages
        jsr loadlib
        cmp #0
        bne linked
        #copy16 msg_noi2c,radiomsg
        rts

linked  sta i2creset+2
        sta i2cpreprw+2
        sta i2creadrg+2
        sta i2cwritrg+2

        lda #8
        sta rtry
try     jsr i2creset
        jsr rdelay        ;let the tuner settle
        #ldxy i2cbuf
        lda #2
        jsr i2cpreprw
        lda #radioadr
        ldy #chipidrg
        clc
        jsr i2creadrg
        bne again
        lda i2cbuf
        cmp #chipidvl
        beq okc
again   dec rtry
        bne try
        #copy16 msg_nordo,radiomsg
        rts
okc     #copy16 msg_rdyok,radiomsg
        rts
        .bend

;~80ms settle delay.
rdelay
        .block
        ldx #$40
o       ldy #0
p       dey
        bne p
        dex
        bne o
        rts
        .bend

msgcmd   ;A -> Msg Command
        .block

        ;"Menu Enquiry" and "Menu Cmd"
        ;message types must be handled
        ;to support menu actions.

        #switch 4
        .byte mc_col
        .byte mc_menq,mc_mnu
        .byte mc_rssi
        .rta setcolr
        .rta mnuenq,mnucmd
        .rta dorssi

done     sec            ;Msg Not Handled
        rts

setcolr  ;X -> Color Code
        stx strcolor

        ldx layer+slindx
        jsr markredraw

        clc            ;Msg Was Handled
        rts

dorssi   ;timer asked for an RSSI refresh (app ctx)
        jsr r_rssi
        lda #1
        sta rssireq
        ldx layer+slindx
        jsr markredraw
        clc
        rts

mnuenq   ;X -> Menu Action Code
        lda #0 ;Enabled, Not Selected
        rts

mnucmd   ;X -> Menu Action Code
        txa
        #switch 1
        .text "!"
        .rta quitapp

        sec ;Action Code Not Recognized
        rts
        .bend

.comment
drawmain
        .block
        ;Configure the Draw Context
        #ldxy drawctx
        jsr setctx

        ;Set Draw Properties and Color
        ldx #(d_crsr_h|d_petscr)
        ldy strcolor
        jsr setdprops

        ;Clear the Draw Context
        lda #" "
        jsr ctxclear

        ;Set Context Draw Position

        #ldxy 5   ;Row  5
        clc
        jsr setlrc

        #ldxy 11  ;Col 11     (40-18)/2
        sec
        jsr setlrc

        ;Loop over message, outputting
        ;with calls to ctxdraw.

        ldx #0
next    lda hello_s,x
        beq done
        jsr ctxdraw
        inx
        bne next

done    rts
        .bend
.endcomment

; ------------------------------------
l_update
        .block

        ;Service a timer-requested RSSI refresh here,
        ;in the draw phase (safe for I2C + Toolkit).
        lda rssireq
        beq draw
        lda #0
        sta rssireq
        #ldxy tkenv
        jsr settkenv
        jsr updbars       ;refresh bars from st_vol / st_rssi
        lda tkenv+te_flags
        ora #tf_dirty
        sta tkenv+te_flags

draw    #ldxy tkenv
        jsr tkupdate

        ldy tkenv+te_posy
        ldx tkenv+te_posx
        jmp ctx2scr

        .bend

; ------------------------------------
l_mouse
        .block

        #ldxy tkenv
        jsr tkmouse
        jmp chkdirt

        .bend

; ------------------------------------
l_cmd
        .block

        #ldxy tkenv
        jsr tkkcmd
        jmp chkdirt

        .bend

; ------------------------------------
l_prnt
        .block

        #ldxy tkenv
        jsr tkkprnt
        jmp chkdirt

        .bend

; ------------------------------------
thisdirt
        #setflag this,dflags,df_dirty
        rts

; ------------------------------------
chkdirt
        lda tkenv+te_flags
        and #tf_dirty
        bne redraw
        sec
        rts

; ------------------------------------
mkdirt
        lda tkenv+te_flags
        ora #tf_dirty
        sta tkenv+te_flags

redraw

        ldx layer+slindx
        jsr markredraw

        clc
        rts

;=======================================
;RDA5807 control (via i2c.lib)
;=======================================

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
        bne fail
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
fail    rts
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
        ldx #w_stat
        jmp slabel
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
fail    rts
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

;=======================================
;Display
;=======================================

;Format st_freq into freqstr as "NNN.NMHz".
freqfmt
        .block
        lda st_freq
        sta dlo
        lda st_freq+1
        sta dhi
        lda #0
        sta whole
loop    lda dhi
        bne sub
        lda dlo
        cmp #10
        bcc div
sub     lda dlo
        sec
        sbc #10
        sta dlo
        lda dhi
        sbc #0
        sta dhi
        inc whole
        jmp loop
div     lda dlo
        sta frac
        ldx #0
        lda whole
        cmp #100          ;always emit a hundreds cell
        bcc sp            ;(space or '1') so the string is a
        sbc #100          ;constant 8 chars -> clean redraw
        sta whole
        lda #"1"
        bne hd
sp      lda #" "
hd      sta freqstr,x
        inx
        ldy #0
tens    lda whole
        cmp #10
        bcc tdn
        sec
        sbc #10
        sta whole
        iny
        jmp tens
tdn     tya
        ora #"0"
        sta freqstr,x
        inx
        lda whole
        ora #"0"
        sta freqstr,x
        inx
        lda #"."
        sta freqstr,x
        inx
        lda frac
        ora #"0"
        sta freqstr,x
        inx
        lda #"M"
        sta freqstr,x
        inx
        lda #"H"
        sta freqstr,x
        inx
        lda #"z"
        sta freqstr,x
        inx
        lda #0
        sta freqstr,x
        rts
        .bend

;Reflect the state model on the widgets.
updui
        .block
        #ldxy tkenv
        jsr settkenv
        ;Power
        #copy16 s_pwrof,mktp
        lda st_pwr
        beq p0
        #copy16 s_pwron,mktp
p0      ldx #w_pwr
        jsr stitle
        ;Bass
        #copy16 s_basof,mktp
        lda st_bass
        beq b0
        #copy16 s_bason,mktp
b0      ldx #w_bass
        jsr stitle
        ;Mute
        #copy16 s_mtof,mktp
        lda st_mute
        beq m0
        #copy16 s_mton,mktp
m0      ldx #w_mute
        jsr stitle
        ;Stereo/Mono
        #copy16 s_stereo,mktp
        lda st_ster
        beq s0
        #copy16 s_mono,mktp
s0      ldx #w_ster
        jsr stitle
        ;De-emphasis
        #copy16 s_deem50,mktp
        lda st_deem
        beq e0
        #copy16 s_deem75,mktp
e0      ldx #w_deem
        jsr stitle
        ;Frequency
        jsr freqfmt
        #copy16 freqstr,mktp
        ldx #w_freq
        jsr slabel
        jsr updbars
        rts
        .bend

;Set button[widget X] title = mktp, mark dirty.
stitle
        .block
        txa
        asl
        tax
        lda widgets,x
        sta stmp
        lda widgets+1,x
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        ldy #settitle_
        jsr getmethod
        #rdxy mktp
        jsr sysjmp
        #setflag this,dflags,df_dirty
        rts
        .bend

;Set label[widget X] string = mktp, mark dirty.
slabel
        .block
        txa
        asl
        tax
        lda widgets,x
        sta stmp
        lda widgets+1,x
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        ldy #setstrp_
        jsr getmethod
        lda mktp
        ldx mktp+1
        jsr sysjmp
        #setflag this,dflags,df_dirty
        rts
        .bend

;Update both level bars from st_vol / st_rssi (0..8).
updbars
        .block
        lda st_vol
        clc
        adc #1
        lsr                ;(vol+1)/2 -> 0..8
        ldx #0
        jsr setbar
        lda st_rssi
        lsr
        lsr
        lsr                ;rssi>>3 -> 0..15
        cmp #9
        bcc rok
        lda #8             ;clamp to full
rok     ldx #8
        jmp setbar
        .bend

;Set a bar's 8 cells. A=level 0..8, X=start index
;(0=volume, 8=rssi) into barcells. Filled cells draw
;reverse-video (solid block); empty cells draw space.
setbar
        .block
        sta blev
        txa
        asl
        sta bofs
        lda #0
        sta bidx
sc      lda bidx
        cmp blev          ;C clear if bidx<blev -> on
        lda #f_rev
        bcc on
        lda #0
on      sta btmp
        lda bidx
        asl
        clc
        adc bofs
        tay
        lda barcells,y
        sta stmp
        iny
        lda barcells,y
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        lda btmp
        ldy #strflgs
        sta (this),y
        #setflag this,dflags,df_dirty
        inc bidx
        lda bidx
        cmp #8
        bcc sc
        rts
        .bend

;Timer trigger: post an async app message so the
;I2C read happens in msgcmd (normal app context);
;calling the I2C library from here corrupts things.
tmrtick
        .block
        pha
        txa
        pha
        tya
        pha
        lda #mc_rssi
        ldx #0
        ldy #0
        clc               ;deliver without delay
        jsr msgapp
        pla
        tay
        pla
        tax
        pla
        rts
        .bend

;=======================================
;UI construction
;=======================================

;Create a push button.
;A=offtop,X=offleft,mkw=width,mktp=title,mktg=target.
;Returns RegPtr to the object.
mkbtn
        .block
        sta mktop
        stx mkleft
        ldx #tkbutton
        jsr classptr
        jsr tknew
        #stxy mkobj
        ldy #init_
        jsr getmethod
        jsr sysjmp
        #setobj8 this,btype,bt_psh
        #setobj8 this,rsmask,%00000101
        lda mktop
        ldy #offtop
        sta (this),y
        lda mkleft
        ldy #offleft
        sta (this),y
        lda mkw
        ldy #width
        sta (this),y
        ldy #settitle_
        jsr getmethod
        #rdxy mktp
        jsr sysjmp
        ldy #settgt_
        jsr getmethod
        lda #0
        ldx mktg
        ldy mktg+1
        jsr sysjmp
        #rdxy tkenv+te_rview
        jsr appendto
        #rdxy mkobj
        rts
        .bend

;Create a label.
;A=offtop,X=offleft,mkw=width,mkflg=strflags,mktp=string.
;Returns RegPtr to the object.
mklbl
        .block
        sta mktop
        stx mkleft
        ldx #tklabel
        jsr classptr
        jsr tknew
        #stxy mkobj
        ldy #init_
        jsr getmethod
        jsr sysjmp
        #setobj8 this,rsmask,%00000101
        lda mktop
        ldy #offtop
        sta (this),y
        lda mkleft
        ldy #offleft
        sta (this),y
        lda mkw
        ldy #width
        sta (this),y
        lda mkflg
        ldy #strflgs
        sta (this),y
        ldy #setstrp_
        jsr getmethod
        lda mktp
        ldx mktp+1
        jsr sysjmp
        #rdxy tkenv+te_rview
        jsr appendto
        #rdxy mkobj
        rts
        .bend

;Create an 8-cell horizontal bar of 1-wide labels.
;A=start index (0 or 8), X=start column, brow=row.
mkbar
        .block
        stx bcol
        asl               ;start*2 = byte offset base
        sta bofs
        lda #0
        sta bidx
nc      #copy16 s_cell,mktp
        lda #0
        sta mkflg
        lda #1
        sta mkw
        lda bcol
        clc
        adc bidx          ;column = bcol + idx
        tax
        lda brow          ;offtop = row
        jsr mklbl
        lda bidx
        asl
        clc
        adc bofs
        tay
        lda mkobj
        sta barcells,y
        lda mkobj+1
        iny
        sta barcells,y
        inc bidx
        lda bidx
        cmp #8
        bcc nc
        rts
        .bend

;Build the whole radio UI.
buildui
        .block
        ;frequency (centered)
        jsr freqfmt
        #copy16 freqstr,mktp
        lda #36
        sta mkw
        lda #3
        sta mkflg
        lda #1
        ldx #2
        jsr mklbl
        #storeset widgets,w_freq
        ;status (probe result)
        #copyptr radiomsg,mktp
        lda #36
        sta mkw
        lda #0
        sta mkflg
        lda #18
        ldx #2
        jsr mklbl
        #storeset widgets,w_stat
        ;--- left column ---
        #copy16 s_pwrof,mktp
        #copy16 a_power,mktg
        lda #16
        sta mkw
        lda #3
        ldx #2
        jsr mkbtn
        #storeset widgets,w_pwr
        #copy16 s_stereo,mktp
        #copy16 a_ster,mktg
        lda #16
        sta mkw
        lda #5
        ldx #2
        jsr mkbtn
        #storeset widgets,w_ster
        #copy16 s_basof,mktp
        #copy16 a_bass,mktg
        lda #16
        sta mkw
        lda #7
        ldx #2
        jsr mkbtn
        #storeset widgets,w_bass
        #copy16 s_mtof,mktp
        #copy16 a_mute,mktg
        lda #16
        sta mkw
        lda #9
        ldx #2
        jsr mkbtn
        #storeset widgets,w_mute
        #copy16 s_deem50,mktp
        #copy16 a_deem,mktg
        lda #16
        sta mkw
        lda #11
        ldx #2
        jsr mkbtn
        #storeset widgets,w_deem
        ;--- right column ---
        ;volume (- then +)
        #copy16 s_voldn,mktp
        #copy16 a_vold,mktg
        lda #8
        sta mkw
        lda #3
        ldx #21
        jsr mkbtn
        #storeset widgets,w_vold
        #copy16 s_volup,mktp
        #copy16 a_volu,mktg
        lda #8
        sta mkw
        lda #3
        ldx #29
        jsr mkbtn
        #storeset widgets,w_volu
        ;scan (<< then >>)
        #copy16 s_scndn,mktp
        #copy16 a_scnd,mktg
        lda #8
        sta mkw
        lda #5
        ldx #21
        jsr mkbtn
        #storeset widgets,w_scnd
        #copy16 s_scnup,mktp
        #copy16 a_scnu,mktg
        lda #8
        sta mkw
        lda #5
        ldx #29
        jsr mkbtn
        #storeset widgets,w_scnu
        ;frequency (-- - ++ +)
        #copy16 s_fmdn,mktp
        #copy16 a_fmd,mktg
        lda #4
        sta mkw
        lda #7
        ldx #21
        jsr mkbtn
        #storeset widgets,w_fmd
        #copy16 s_fkdn,mktp
        #copy16 a_fkd,mktg
        lda #4
        sta mkw
        lda #7
        ldx #29
        jsr mkbtn
        #storeset widgets,w_fkd
        #copy16 s_fmup,mktp
        #copy16 a_fmu,mktg
        lda #4
        sta mkw
        lda #7
        ldx #25
        jsr mkbtn
        #storeset widgets,w_fmu
        #copy16 s_fkup,mktp
        #copy16 a_fku,mktg
        lda #4
        sta mkw
        lda #7
        ldx #33
        jsr mkbtn
        #storeset widgets,w_fku
        ;horizontal level bars: "Vol"/"Rss" + 8 cells
        #copy16 s_lvol,mktp
        lda #3
        sta mkw
        lda #0
        sta mkflg
        lda #9
        ldx #21
        jsr mklbl
        lda #9
        sta brow
        lda #0
        ldx #25
        jsr mkbar
        #copy16 s_lrss,mktp
        lda #3
        sta mkw
        lda #0
        sta mkflg
        lda #10
        ldx #21
        jsr mklbl
        lda #10
        sta brow
        lda #8
        ldx #25
        jsr mkbar
        rts
        .bend

;=======================================
;Button targets (this = button on entry)
;=======================================

a_power
        .block
        #pushptr this
        lda st_pwr
        eor #1
        sta st_pwr
        jsr r_power
        lda st_pwr
        beq skip
        jsr applyall
skip    jsr updui
        jmp cbend
        .bend

a_ster
        .block
        #pushptr this
        lda st_ster
        eor #1
        sta st_ster
        jsr r_stereo
        jsr updui
        jmp cbend
        .bend

a_bass
        .block
        #pushptr this
        lda st_bass
        eor #1
        sta st_bass
        jsr r_bass
        jsr updui
        jmp cbend
        .bend

a_mute
        .block
        #pushptr this
        lda st_mute
        eor #1
        sta st_mute
        jsr r_mute
        jsr updui
        jmp cbend
        .bend

a_deem
        .block
        #pushptr this
        lda st_deem
        eor #1
        sta st_deem
        jsr r_deem
        jsr updui
        jmp cbend
        .bend

a_volu
        .block
        #pushptr this
        lda st_vol
        cmp #vol_max
        bcs done
        inc st_vol
done    jsr r_vol
        jsr updui
        jmp cbend
        .bend

a_vold
        .block
        #pushptr this
        lda st_vol
        beq done
        dec st_vol
done    jsr r_vol
        jsr updui
        jmp cbend
        .bend

a_scnu
        .block
        #pushptr this
        lda #1
        jsr r_scan
        jsr r_scanwait
        jsr r_getfreq
        jsr updui
        jmp cbend
        .bend

a_scnd
        .block
        #pushptr this
        lda #0
        jsr r_scan
        jsr r_scanwait
        jsr r_getfreq
        jsr updui
        jmp cbend
        .bend

a_fmu
        .block
        #pushptr this
        lda #10           ;+1 MHz
        jsr addfreq
        jmp cbend
        .bend

a_fku
        .block
        #pushptr this
        lda #1            ;+100 kHz
        jsr addfreq
        jmp cbend
        .bend

a_fmd
        .block
        #pushptr this
        lda #10           ;-1 MHz
        jsr subfreq
        jmp cbend
        .bend

a_fkd
        .block
        #pushptr this
        lda #1            ;-100 kHz
        jsr subfreq
        jmp cbend
        .bend

;Add A (100kHz units) to st_freq; wrap to frq_min
;if it exceeds frq_max. Pushes freq and refreshes.
addfreq
        .block
        clc
        adc st_freq
        sta st_freq
        lda st_freq+1
        adc #0
        sta st_freq+1
        lda #>frq_max
        cmp st_freq+1
        bcc wrap
        bne done
        lda #<frq_max
        cmp st_freq
        bcs done
wrap    #copy16 frq_min,st_freq
done    jsr r_freq
        jmp updui
        .bend

;Subtract A (100kHz units) from st_freq; wrap to
;frq_max if it drops below frq_min. Pushes+refreshes.
subfreq
        .block
        sta updtmp
        lda st_freq
        sec
        sbc updtmp
        sta st_freq
        lda st_freq+1
        sbc #0
        sta st_freq+1
        lda st_freq+1
        cmp #>frq_min
        bcc wrap
        bne done
        lda st_freq
        cmp #<frq_min
        bcs done
wrap    #copy16 frq_max,st_freq
done    jsr r_freq
        jmp updui
        .bend

;Common callback tail: restore this, mark dirty.
cbend
        #pullxy
        jsr ptrthis
        jmp mkdirt

;---------------------------------------
externs  ;C64 OS KERNAL Link Table

        #inc_h "memory"
pgalloc     #syscall lmem,pgalloc_
memcpy      #syscall lmem,memcpy_
pgfree      #syscall lmem,pgfree_

        #inc_h "screen"
        #inc_h "util.frame"
markredraw  #syscall lscr,markredraw_         
layerpush   #syscall lscr,layerpush_
setlrc      #syscall lscr,setlrc_
setdprops   #syscall lscr,setdprops_
ctxclear    #syscall lscr,ctxclear_
ctxdraw     #syscall lscr,ctxdraw_
ctx2scr     #syscall lscr,ctx2scr_

         #inc_h "service"
quitapp     #syscall lser,quitapp_
loadlib     #syscall lser,loadlib_
unldlib     #syscall lser,unldlib_

         #inc_h "timers"
timeque     #syscall ltim,timeque_
msgapp      #syscall ltim,msgapp_

         #inc_h "toolkit"
setctx      #syscall ltkt,setctx_
classptr    #syscall ltkt,classptr_
tknew       #syscall ltkt,tknew_
appendto    #syscall ltkt,appendto_
getmethod   #syscall ltkt,getmethod_
tkupdate    #syscall ltkt,tkupdate_
tkmouse     #syscall ltkt,tkmouse_
ptrthis     #syscall ltkt,ptrthis_
tkkcmd      #syscall ltkt,tkkcmd_
tkkprnt     #syscall ltkt,tkkprnt_
settkenv    #syscall ltkt,settkenv_
         .byte $ff ;kernal link table terminator

;---------------------------------------
;i2c.lib.r jump table. High bytes are
;patched at runtime by radioinit with the
;page returned from loadlib.
        #inc_h "io_i2c"
i2creset  jmp reset_
i2cpreprw jmp prep_rw_
i2creadrg jmp readreg_
i2cwritrg jmp writreg_
