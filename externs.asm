;---------------------------------------
externs  ;C64 OS KERNAL Link Table

        #inc_h "memory"
pgalloc     #syscall lmem,pgalloc_

        #inc_h "screen"
markredraw  #syscall lscr,markredraw_         
layerpush   #syscall lscr,layerpush_
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
