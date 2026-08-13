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
        #inc_s "file"

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
m_st     = $04     ;stereo indicator (reg 0x0A bit10, hi byte)
m_lnap   = $c0     ;LNA antenna-port mask (reg 0x05 lo)
lna_port = $c0     ;$80 = LNAP input (RDA5807 reset default), $40 = LNAN, $c0 = DUAL (both inputs — often best)
vol_max  = $0f
rssi_flr = 15      ;RSSI noise floor (bar empty at/below this)
rssi_top = 63      ;RSSI at full bar (useful window = flr..top)
frq_min  = 870     ;87.0 MHz (100kHz units)
frq_max  = 1080    ;108.0 MHz
c_on     = cgreen  ;toggle button on colour
c_off    = cdgrey  ;toggle button off colour

;--- debug ---
DEBUG    = 1       ;1 = log each i2c register write in the status label; set 0 to remove
log_ttl  = 10      ;log line auto-clears after this many 2s poll ticks (~20s)

;custom async message code (timer trigger -> msgcmd)
mc_rssi  = $80

;--- widget store indices ---
w_freq = 0
w_stat = 1
w_pwr  = 2
w_ster = 3
w_bass = 4
w_mute = 5
w_e50  = 6
w_volu = 7
w_vold = 8
w_scnu = 9
w_scnd = 10
w_fmu  = 11
w_fmd  = 12
w_fku  = 13
w_fkd  = 14
w_e75  = 15
w_stind = 16
w_save = 17
w_name = 18

;--- presets ---
NPRESET  = 8       ;max stored channel presets
prsize   = 19      ;record: used(1) + freq(2) + name(16)
pnamlen  = 16
cfg_ver  = 1       ;config.i format version
tkinpages = 6      ;pages allocated for the loaded tkinput.r class

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
drawctx  .word 0           ;Char Origin (private buffer, set in init)
         .word 0           ;Colr Origin (private buffer, set in init)
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
st_stind .byte 0       ;stereo indicator 0/1
st_psel  .byte $ff     ;selected preset slot ($ff=none)

;--- widget pointer store (w_* indices) ---
widgets  .word 0,0,0,0,0,0,0,0
         .word 0,0,0,0,0,0,0,0
         .word 0,0,0

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
bst      .byte 0
mkbt     .byte 0
ptmp     .byte 0
ptmp2    .byte 0
pidx     .byte 0
i2cstat  .byte 0       ;0=I2C ok, 1=comms error (shown in status label)
logttl   .byte 0       ;log-line auto-clear countdown (2s ticks)
rssireq  .byte 0       ;set by timer, serviced in l_update
frqbad   .byte 0       ;1=chip read was out-of-band (unconfigured)
freqstr  .byte 0,0,0,0,0,0,0,0,0,0,0,0
topfstr  .byte 0,0,0,0,0,0,0,0,0,0   ;top freq label (own buffer)
statbuf  .fill 37,0     ;status/log line, space-padded to 36
.if DEBUG
dbgstr   .fill 20,0
.endif

;bar cell label pointers: [0..14]=volume, [15..29]=rssi
barcells .word 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
         .word 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

;preset UI pointers + data
pnamlbl  .word 0,0,0,0,0,0,0,0   ;name label ptrs
pradbtn  .word 0,0,0,0,0,0,0,0   ;radio button ptrs
pfrqlbl  .word 0,0,0,0,0,0,0,0   ;freq label ptrs
pfrqstr  .fill NPRESET*9,0       ;per-preset formatted "NNN.NMHz"
pfbase   .byte 0                 ;pfmt scratch (slot*9 base)

;config block persisted to config.i. Extensible: add new
;settings between cfgpsz and presets and bump cfg_ver.
cfgblk
cfgvers  .byte cfg_ver          ;format version
cfgnpre  .byte NPRESET           ;number of preset slots
cfgpsz   .byte prsize            ;record size
presets  .fill NPRESET*prsize,0  ;[used,freqLo,freqHi,name x16] x N
cfgsize  = *-cfgblk
namebuf  .fill 17,0            ;TKInput backing store (16 chars + null)
tkincls  .word 0               ;loaded TKInput class pointer (0 = none)
clspg    .byte 0               ;class-load scratch (fref page)
sclsp    .word 0               ;superclass ptr saved across class load

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
msg_i2cer .null "Failed to communicate with RDA5807"
msg_full  .null "Presets full"

s_pwron  .text "Power "
         .byte $ab,0
s_pwrof  .text "Power "
         .byte $aa,0
s_stereo .null "Stereo"
s_lbass  .null "Bass Boost"
s_lmute  .null "Mute"
s_e50    .null "Emph 50us"
s_e75    .null "Emph 75us"
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
s_save   .null "Store"
s_del    .null "Del"
s_name   .null "Name:"
s_appttl .null "FM Radio"
s_tkdir  .null "tk"
s_tkinr  .null "tkinput.r"
s_cfgnm  .null "config.i"
s_empty  .null ""
s_cell   .byte $20,0        ;1-char bar cell (reversed = solid block)
stindstr .text "Stereo "
         .byte $aa,0

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
        jsr readstate      ;power/settings from the chip are
        jsr r_stind        ;authoritative (correct whether it is
                           ;powered off or freshly reset)
        lda frqbad
        beq nordf
        jsr r_freq         ;out-of-band tuning -> write the clamped
nordf                      ;default channel; leaves power untouched

        ;Load saved presets/settings (missing file -> defaults)
        jsr loadcfg

        ;Allocate a private layer buffer (char + color) so the
        ;Toolkit draws into it and ctx2scr composites to the
        ;system screen. Drawing straight to $0400/$d800 bypasses
        ;the compositor and breaks menu/utility layering + keys.
        lda #mapapp
        ldx #4
        jsr pgalloc
        sty drawctx+d_coloro+1
        lda #mapapp
        ldx #4
        jsr pgalloc
        sty drawctx+d_origin+1

        ; Allocate memory for tk widgets
        lda #mapapp
        ldx #18 ;UI object pool (~77 objects)
        jsr pgalloc
        sty tkenv+te_mpool

        ;Load Shared Libraries

        ;Load Custom TK Classes
        #ldxy tkenv
        jsr settkenv

        ;Load & link the TKInput class from //os/tk/
        ldx #"p"          ;path.lib
        ldy #"a"
        lda #2
        jsr loadlib
        cmp #0
        beq noinput       ;path.lib missing -> skip TKInput
        sta plsetnm+2
        sta plpthad+2
        sta plgopa+2
        ldx #tkctrl       ;superclass = TKCtrl
        jsr classptr
        stx sclsp         ;save it: pgalloc/path.lib may use zp $2b-$2e
        sty sclsp+1
        lda #mapapp
        ldx #tkinpages
        jsr pgalloc
        sty clspg
        tya               ;A = fref page
        ldx #"s"          ;system dir
        jsr plgopa
        lda clspg
        ldx #<s_tkdir
        ldy #>s_tkdir
        jsr plpthad       ;-> //os/tk/
        lda clspg
        ldx #<s_tkinr
        ldy #>s_tkinr
        jsr plsetnm       ;tkinput.r
        lda sclsp         ;restore superclass into `class` for linking
        sta class
        lda sclsp+1
        sta class+1
        ldy clspg
        ldx #0
        jsr loadreloc     ;loads + auto-links to TKCtrl
        ldx class         ;link routine leaves the class ptr in `class`
        ldy class+1
        #stxy tkincls
        ldx #"p"          ;path.lib no longer needed
        ldy #"a"
        lda #0
        jsr unldlib
noinput

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
        lda #log_ttl       ;start the log auto-clear countdown
        sta logttl

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

        lda layer+slindx   ;tell the toolkit which layer it lives on,
        sta tkenv+te_layer ;else the env is treated as blurred (no keys)

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

        ;Persist presets/settings
        jsr savecfg

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
        jsr r_stind
        lda logttl        ;log-line auto-clear countdown
        beq lc0
        dec logttl
        bne lc0
        jsr logclr
lc0     lda #1
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
        jsr updstind
        jsr psync         ;auto-select matching preset radio
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
        #ldxy tkenv        ;toolkit routes keys to the focused TKInput
        jsr tkkprnt
        lda tkenv+te_flags ;force a redraw so typed text shows
        ora #tf_dirty
        sta tkenv+te_flags
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

;=======================================
;Display
;=======================================

;Format st_freq into freqstr as "NNN.NMHz".
freqfmt
        lda st_freq
        sta dlo
        lda st_freq+1
        sta dhi
;Format the frequency in dlo/dhi into freqstr.
freqfmtd
        .block
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
        ;Power (push button title)
        #copy16 s_pwrof,mktp
        lda st_pwr
        beq p0
        #copy16 s_pwron,mktp
p0      ldx #w_pwr
        jsr stitle
        ;Stereo checkbox (checked = stereo)
        lda st_ster
        eor #1
        ldx #w_ster
        jsr sstate
        ;Bass Boost checkbox
        lda st_bass
        ldx #w_bass
        jsr sstate
        ;Mute checkbox
        lda st_mute
        ldx #w_mute
        jsr sstate
        ;De-emphasis radios (50us=deem0, 75us=deem1)
        lda st_deem
        eor #1
        ldx #w_e50
        jsr sstate
        lda st_deem
        ldx #w_e75
        jsr sstate
        ;Frequency
        jsr freqfmt
        ldx #0             ;copy to own buffer; updpres/pfmt
c8      lda freqstr,x      ;reuse freqstr, so the top label
        sta topfstr,x      ;needs a private copy to survive
        beq c8d
        inx
        cpx #10
        bcc c8
c8d     #copy16 topfstr,mktp
        ldx #w_freq
        jsr slabel
        jsr updbars
        jsr updstind
        jsr updpres
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

;Show mktp's string on the status/log line, space-
;padded to the full 36-wide field, so leftover
;characters from a previous (longer) message are
;cleared.
setstat
        .block
        #rdxy mktp
        jsr ptrthis        ;this -> source string
        ldy #0
cp      lda (this),y
        beq pad
        sta statbuf,y
        iny
        cpy #36
        bcc cp
        bcs term           ;filled 36 -> stop
pad     lda #" "
pl      sta statbuf,y
        iny
        cpy #36
        bcc pl
term    lda #0
        sta statbuf,y
        lda #log_ttl       ;restart auto-clear countdown
        sta logttl
        #copy16 statbuf,mktp
        ldx #w_stat
        jmp slabel
        .bend

;Show the I2C comms-error message in the status label,
;once, when entering the error state (avoids flicker).
;Safe before the UI exists (checks the w_stat pointer).
i2cbad
        .block
        lda widgets+w_stat*2
        ora widgets+w_stat*2+1
        beq done          ;UI not built yet
        lda i2cstat
        bne done          ;already showing the error
        lda #1
        sta i2cstat
        #copy16 msg_i2cer,mktp
        jmp setstat
done    rts
        .bend

;Clear the error: restore the probe message in the
;status label, once, when comms recovers.
i2cok
        .block
        lda widgets+w_stat*2
        ora widgets+w_stat*2+1
        beq done          ;UI not built yet
        lda i2cstat
        beq done          ;already ok
        lda #0
        sta i2cstat
        #copyptr radiomsg,mktp
        jmp setstat
done    rts
        .bend

;Blank the log/status line (auto-clear timeout). Does
;not go through setstat, so it leaves logttl at 0.
logclr
        .block
        ldy #0
        lda #" "
sp      sta statbuf,y
        iny
        cpy #36
        bcc sp
        lda #0
        sta statbuf,y
        sta i2cstat        ;clear latch so a persistent error can re-show
        #copy16 statbuf,mktp
        ldx #w_stat
        jmp slabel
        .bend

;Set checkbox/radio[widget X] cf_state = A (0/1),
;then mark dirty.
sstate
        .block
        sta bst
        txa
        asl
        tax
        lda widgets,x
        sta stmp
        lda widgets+1,x
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        ldy #cflags
        lda (this),y
        and #(255-cf_state)
        ldx bst
        beq wr
        ora #cf_state
wr      sta (this),y
        #setflag this,dflags,df_dirty
        rts
        .bend

;Show "Stereo X" ($ab=stereo, $aa=mono) under RSS bar.
updstind
        .block
        lda #$aa
        ldx st_stind
        beq set
        lda #$ab
set     sta stindstr+7
        #copy16 stindstr,mktp
        ldx #w_stind
        jmp slabel
        .bend

;Update both level bars from st_vol / st_rssi (0..15).
updbars
        .block
        lda st_vol         ;0..15 -> full-scale bar
        ldx #0
        jsr setbar
        ;RSSI is logarithmic (dB-like). Drop the noise
        ;floor, then span flr..top linearly (in dB) over
        ;the 15 cells: level = (rssi-15) * 5 / 16.
        lda st_rssi
        sec
        sbc #rssi_flr
        bcc rzero          ;below floor -> empty
        cmp #(rssi_top-rssi_flr+1)
        bcc rin
        lda #(rssi_top-rssi_flr) ;clamp to window top
rin     sta updtmp
        asl
        asl
        clc
        adc updtmp         ;x5
        lsr
        lsr
        lsr
        lsr                ;/16 -> 0..15
        jmp rset
rzero   lda #0
rset    ldx #15
        jmp setbar
        .bend

;Set a bar's 15 cells. A=level 0..15, X=start index
;(0=volume, 15=rssi) into barcells. Filled cells draw
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
        cmp #15
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
        lda mkbt
        ldy #btype
        sta (this),y
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

;Create a 15-cell horizontal bar of 1-wide labels.
;A=start index (0 or 15), X=start column, brow=row.
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
        ;cell colour: green 0..9, yellow 10..13, red 14
        lda #cgreen
        ldx bidx
        cpx #10
        bcc ccol
        lda #cyellow
        cpx #14
        bne ccol
        lda #cred
ccol    sta btmp
        #rdxy mkobj
        jsr ptrthis
        lda btmp
        ldy #bcolor
        sta (this),y
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
        cmp #15
        bcc nc
        rts
        .bend

;Build the whole radio UI.
buildui
        .block
        ;app title (top left, same row as centered freq)
        #copy16 s_appttl,mktp
        lda #8
        sta mkw
        lda #0
        sta mkflg
        lda #1
        ldx #2
        jsr mklbl
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
        lda #23
        ldx #2
        jsr mklbl
        #storeset widgets,w_stat
        ;--- left column ---
        ;Power (push button)
        lda #bt_psh
        sta mkbt
        #copy16 s_pwrof,mktp
        #copy16 a_power,mktg
        lda #9
        sta mkw
        lda #3
        ldx #2
        jsr mkbtn
        #storeset widgets,w_pwr
        ;Stereo / Bass Boost / Mute (checkboxes)
        lda #bt_chk
        sta mkbt
        #copy16 s_stereo,mktp
        #copy16 a_ster,mktg
        lda #16
        sta mkw
        lda #5
        ldx #2
        jsr mkbtn
        #storeset widgets,w_ster
        #copy16 s_lbass,mktp
        #copy16 a_bass,mktg
        lda #16
        sta mkw
        lda #7
        ldx #2
        jsr mkbtn
        #storeset widgets,w_bass
        #copy16 s_lmute,mktp
        #copy16 a_mute,mktg
        lda #16
        sta mkw
        lda #9
        ldx #2
        jsr mkbtn
        #storeset widgets,w_mute
        ;De-emphasis (linked radio pair)
        lda #bt_rad
        sta mkbt
        #copy16 s_e50,mktp
        #copy16 a_e50,mktg
        lda #16
        sta mkw
        lda #11
        ldx #2
        jsr mkbtn
        #storeset widgets,w_e50
        #copy16 s_e75,mktp
        #copy16 a_e75,mktg
        lda #16
        sta mkw
        lda #12
        ldx #2
        jsr mkbtn
        #storeset widgets,w_e75
        ;link radio pair: e50<->e75 via bnext loop
        lda widgets+w_e50*2
        sta stmp
        lda widgets+w_e50*2+1
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        ldy #bnext
        lda widgets+w_e75*2
        sta (this),y
        iny
        lda widgets+w_e75*2+1
        sta (this),y
        lda widgets+w_e75*2
        sta stmp
        lda widgets+w_e75*2+1
        sta stmp+1
        #rdxy stmp
        jsr ptrthis
        ldy #bnext
        lda widgets+w_e50*2
        sta (this),y
        iny
        lda widgets+w_e50*2+1
        sta (this),y
        lda #bt_psh
        sta mkbt
        ;--- right column ---
        ;volume (- then +)
        #copy16 s_voldn,mktp
        #copy16 a_vold,mktg
        lda #8
        sta mkw
        lda #3
        ldx #18
        jsr mkbtn
        #storeset widgets,w_vold
        #copy16 s_volup,mktp
        #copy16 a_volu,mktg
        lda #8
        sta mkw
        lda #3
        ldx #27
        jsr mkbtn
        #storeset widgets,w_volu
        ;scan (<< then >>)
        #copy16 s_scndn,mktp
        #copy16 a_scnd,mktg
        lda #8
        sta mkw
        lda #5
        ldx #18
        jsr mkbtn
        #storeset widgets,w_scnd
        #copy16 s_scnup,mktp
        #copy16 a_scnu,mktg
        lda #8
        sta mkw
        lda #5
        ldx #27
        jsr mkbtn
        #storeset widgets,w_scnu
        ;frequency (-- - ++ +)
        #copy16 s_fmdn,mktp
        #copy16 a_fmd,mktg
        lda #4
        sta mkw
        lda #7
        ldx #18
        jsr mkbtn
        #storeset widgets,w_fmd
        #copy16 s_fkdn,mktp
        #copy16 a_fkd,mktg
        lda #3
        sta mkw
        lda #7
        ldx #28
        jsr mkbtn
        #storeset widgets,w_fkd
        #copy16 s_fmup,mktp
        #copy16 a_fmu,mktg
        lda #4
        sta mkw
        lda #7
        ldx #23
        jsr mkbtn
        #storeset widgets,w_fmu
        #copy16 s_fkup,mktp
        #copy16 a_fku,mktg
        lda #3
        sta mkw
        lda #7
        ldx #32
        jsr mkbtn
        #storeset widgets,w_fku
        ;horizontal level bars: "Vol"/"Rss" + 15 cells
        #copy16 s_lvol,mktp
        lda #3
        sta mkw
        lda #0
        sta mkflg
        lda #9
        ldx #18
        jsr mklbl
        lda #9
        sta brow
        lda #0
        ldx #22
        jsr mkbar
        #copy16 s_lrss,mktp
        lda #3
        sta mkw
        lda #0
        sta mkflg
        lda #10
        ldx #18
        jsr mklbl
        lda #10
        sta brow
        lda #15
        ldx #22
        jsr mkbar
        ;stereo indicator label (under Rss bar)
        #copy16 stindstr,mktp
        lda #10
        sta mkw
        lda #0
        sta mkflg
        lda #11
        ldx #18
        jsr mklbl
        #storeset widgets,w_stind
        ;Save current frequency as a preset
        lda #bt_psh
        sta mkbt
        #copy16 s_save,mktp
        #copy16 a_save,mktg
        lda #7
        sta mkw
        lda #14
        ldx #2
        jsr mkbtn
        #storeset widgets,w_save
        ;Delete the selected preset
        #copy16 s_del,mktp
        #copy16 a_delete,mktg
        lda #5
        sta mkw
        lda #14
        ldx #10
        jsr mkbtn
        ;name entry: "Name:" label + TKInput field
        #copy16 s_name,mktp
        lda #6
        sta mkw
        lda #0
        sta mkflg
        lda #14
        ldx #18
        jsr mklbl
        lda tkincls        ;TKInput class available?
        ora tkincls+1
        beq nofield
        #rdxy tkincls      ;X/Y = class pointer (value, not address)
        jsr tknew
        #stxy mkobj
        ldy #init_
        jsr getmethod
        jsr sysjmp
        ldy #setstr_       ;buffer = namebuf, max 16 chars
        jsr getmethod
        ldx #<namebuf
        ldy #>namebuf
        lda #pnamlen
        jsr sysjmp
        #setobj8 this,rsmask,%00000101
        #setobj8 this,offtop,14
        #setobj8 this,offleft,24
        #setobj8 this,width,15
        #rdxy tkenv+te_rview
        jsr appendto
        jmp namedone
nofield #copy16 namebuf,mktp   ;fallback: blue label (no typing)
        lda #16
        sta mkw
        lda #0
        sta mkflg
        lda #14
        ldx #24
        jsr mklbl
        #rdxy mkobj
        jsr ptrthis
        lda #cblue
        ldy #bcolor
        sta (this),y
namedone
        #rdxy mkobj        ;X/Y = the object (appendto/ptrthis clobbered them)
        #storeset widgets,w_name
        ;preset rows (blue name + radio)
        jsr buildpres
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

a_e50
        .block
        #pushptr this
        lda #0
        sta st_deem
        jsr r_deem
        jsr updui
        jmp cbend
        .bend

a_e75
        .block
        #pushptr this
        lda #1
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

;Select a preset radio (this=radio; tag=slot).
a_preset
        .block
        #pushptr this
        ldy #tag
        lda (this),y
        sta st_psel
        jsr ptune
        jmp cbend
        .bend

;Save the current frequency into the next free preset
;slot, using the typed name (or the frequency if none).
a_save
        .block
        #pushptr this
        jsr pfree
        cmp #$ff
        beq full
        sta st_psel
        jsr precptr        ;A=slot -> stmp=rec
        #rdxy stmp
        jsr ptrthis
        ldy #0
        lda #1
        sta (this),y       ;used=1
        ldy #1
        lda st_freq
        sta (this),y
        iny
        lda st_freq+1
        sta (this),y
        ldx #0             ;copy namebuf, pad with spaces to 16
        ldy #3
cpn     lda namebuf,x
        beq padn
        sta (this),y
        inx
        iny
        cpx #pnamlen
        bcc cpn
        jmp donen
padn    lda #$20
pdn     sta (this),y
        iny
        cpy #(3+pnamlen)
        bcc pdn
donen   jsr updpres
        jsr nameclr        ;clear the input after saving
        jsr savecfg        ;persist to config.i
        jmp cbend
full    #copy16 msg_full,mktp
        jsr setstat
        jmp cbend
        .bend

;Delete the currently selected preset (st_psel), if any,
;then persist.  The freed slot becomes the next Store target.
a_delete
        .block
        #pushptr this
        lda st_psel
        cmp #$ff
        beq nodel          ;nothing selected
        jsr precptr        ;A=slot -> stmp = record
        #rdxy stmp
        jsr ptrthis
        ldy #0
        lda #0
        sta (this),y       ;used=0
        iny
        sta (this),y       ;freq lo=0
        iny
        sta (this),y       ;freq hi=0
        lda #$20           ;name = spaces so the label clears
cl      iny                ;on redraw (labels don't erase)
        sta (this),y
        cpy #(3+pnamlen-1)
        bcc cl
        lda #$ff
        sta st_psel        ;deselect
        jsr updpres
        jsr savecfg
nodel   jmp cbend
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
loadreloc   #syscall lser,loadreloc_

         #inc_h "file"
fopen       #syscall lfil,fopen_
fread       #syscall lfil,fread_
fwrite      #syscall lfil,fwrite_
fclose      #syscall lfil,fclose_

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

;path.lib jump table. High bytes are patched at
;runtime by init with the page from loadlib.
        #inc_h "path"
plsetnm   jmp setname_
plpthad   jmp pathadd_
plgopa    jmp gopath_
