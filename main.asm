;----[ main.a - FM-Radio ]-----------

        .include "os/h/modules.h"

        ;Useful Constants/Macros

        .include "os/s/app.s"
        .include "os/s/colors.s"
        .include "os/s/ctxdraw.s"
        .include "os/s/io.s"
        .include "os/s/pointer.s"
        .include "os/s/switch.s"

        ;Kernal Module Constants

        .include "os/s/screen.s"
        .include "os/s/service.s"
        .include "os/s/toolkit.s"
        .include "os/s/memory.s"

        .include "os/tk/s/tksizes.s"
        .include "os/tk/s/tkview.s"
        .include "os/tk/s/tkctrl.s"
        .include "os/tk/s/tktext.s"

        .include "os/tk/h/tkview.h"
        .include "os/tk/h/tkctrl.h"
        .include "os/tk/h/classes.h"
        .include "os/tk/h/tkobj.h"
        .include "os/tk/h/tktext.h"

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

hello_s  .null "FM Radio app"
test_s   .null "Test Label text"
strcolor .byte clblue
widgets  .word 0,0

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

        ; Allocate memory for tk widgets
        lda #mapapp
        ldx #2 ; Put the value printed by npages here
        jsr pgalloc
        sty tkenv+te_mpool

        #ldxy layer
        jsr layerpush

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

; create test tkLabel

        ldx #tklabel
        jsr classptr
        jsr tknew

        #storeset widgets,0

        ldy #init_
        jsr getmethod
        jsr sysjmp

        #setobj8 this,offtop,1
        #setobj8 this,offbot,1
        #setobj8 this,offleft,0
        #setobj8 this,offrght,0

        ; prepare the pointer 
        ; reference for the function
        ; to set a string pointer

        ldy #setstrp_
        jsr getmethod
        lda #<test_s
        ldx #>test_s
        jsr sysjmp

        #rdxy tkenv+te_rview
        jsr appendto
        ;Load Custom Icons

        ;Initialize UI

        ; push main screen layer ?????????????

        #ldxy layer
        jsr layerpush

        ldx layer+slindx
        jsr markredraw

        rts
        .bend

willquit
        .block
        ;Deallocate resources here.

        ;Unload Shared Libraries

        ;Unload Custom Icons

        rts
        .bend

msgcmd   ;A -> Msg Command
        .block

        ;"Menu Enquiry" and "Menu Cmd"
        ;message types must be handled
        ;to support menu actions.

        #switch 3
        .byte mc_col
        .byte mc_menq,mc_mnu
        .rta setcolr
        .rta mnuenq,mnucmd

done     sec            ;Msg Not Handled
        rts

setcolr  ;X -> Color Code
        stx strcolor

        ldx scrlayer_+slindx
        jsr markredraw

        clc            ;Msg Was Handled
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

        #ldxy tkenv
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

;---------------------------------------
externs  ;C64 OS KERNAL Link Table

        .include "os/h/memory.h"
pgalloc     #syscall lmem,pgalloc_
memcpy      #syscall lmem,memcpy_
pgfree      #syscall lmem,pgfree_

        .include "os/h/screen.h"
        .include "os/h/util.frame.h"
markredraw  #syscall lscr,markredraw_         
layerpush   #syscall lscr,layerpush_
setlrc      #syscall lscr,setlrc_
setdprops   #syscall lscr,setdprops_
ctxclear    #syscall lscr,ctxclear_
ctxdraw     #syscall lscr,ctxdraw_
ctx2scr     #syscall lscr,ctx2scr_

         .include "os/h/service.h"
quitapp     #syscall lser,quitapp_

         .include "os/h/toolkit.h"
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
