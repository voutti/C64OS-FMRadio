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
i2cpages = 3       ;i2c.lib.r size in pages (transport, not chip)
;The RDA5807 chip constants (identity, registers, bit
;masks, band limits, RSSI window) live in rda5807.asm
;so a different tuner only needs that one file swapped.

;--- debug ---
DEBUG    = 0       ;1 = log each i2c register write in the status label; set 0 to remove
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
w_fmlk = 19

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
st_fmtr  .byte 0       ;FM TRUE / station lock 0/1
st_psel  .byte $ff     ;selected preset slot ($ff=none)

;--- widget pointer store (w_* indices) ---
widgets  .word 0,0,0,0,0,0,0,0
         .word 0,0,0,0,0,0,0,0
         .word 0,0,0,0

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
i2cstat  .byte 0       ;displayed comms state (0=ok,1=error); UI latch
i2cres   .byte 0       ;raw last I2C result from the driver (0=ok,1=error)
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
s_titfm  .null "FM"
s_titrad .null "Radio"
s_tkdir  .null "tk"
s_tkinr  .null "tkinput.r"
s_cfgnm  .null "config.i"
s_empty  .null ""
s_cell   .byte $20,0        ;1-char bar cell (reversed = solid block)
stindstr .text "Stereo "
         .byte $aa,0
fmlkstr  .text "FM Lock "
         .byte $aa,0
;App icon rows: the 3x3 icon glyphs are resident at screen
;codes $f7-$ff (top $f7-$f9, mid $fa-$fc, bottom $fd-$ff).
icnrow0  .byte $f7,$f8,$f9,0
icnrow1  .byte $fa,$fb,$fc,0
icnrow2  .byte $fd,$fe,$ff,0

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
        #switch 3
        .byte mc_menq,mc_mnu
        .byte mc_rssi
        .rta mnuenq,mnucmd
        .rta dorssi

done     sec            ;Msg Not Handled
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

; ------------------------------------
l_update
        .block

        jsr synci2c        ;reflect the driver's last I2C result in the status label

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
        jsr updfmlk
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
;Modules (assembled into one binary; the
;codebase uses a single flat namespace, so
;these are textual .includes, not linked units)
;=======================================
        .include "rda5807.asm"   ;FM tuner chip driver (swap this file per chip)
        .include "ui.asm"        ;display, widget construction, button targets
        .include "presets.asm"   ;channel preset store
        .include "config.asm"    ;config.i load / save
        .include "externs.asm"   ;KERNAL link table + i2c.lib / path.lib jump tables
