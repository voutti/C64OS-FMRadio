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

;Sync the status label to the driver's last I2C result
;(i2cres). Updates the label only on a state change, so
;there's no per-frame churn. Called from l_update.
;Safe before the UI exists (checks the w_stat pointer).
synci2c
        .block
        lda widgets+w_stat*2
        ora widgets+w_stat*2+1
        beq done          ;UI not built yet
        lda i2cres
        cmp i2cstat
        beq done          ;displayed state already matches
        sta i2cstat       ;latch the new displayed state
        lda i2cres
        bne showerr
        #copyptr radiomsg,mktp
        jmp setstat
showerr #copy16 msg_i2cer,mktp
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

