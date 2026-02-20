;----[ modules.h ]----------------------

sltb     = $d000-(2*10)

;Under $cxxx for IDE64

sser     = sltb-$0716
sinp     = sser-$0350
smat     = sinp-$0175
stim     = smat-$021b

smem     = stim-$028a
sstr     = smem-$014d
sfil     = sstr-$0546
sscr     = sfil-$06ae
smnu     = sscr-$08aa
stkt     = smnu-$0557

syscall .segment ;lxxx,routine
         .byte (\1)
         .word (\2)
.endsegment

inc_h .sfunction p1, "os/h/" .. p1 .. ".h"

inc_s .sfunction p1, "os/s/" .. p1 .. ".s"

inc_t .sfunction p1, "os/s/t/" .. p1 .. ".s"

inc_k .sfunction p1, "os/s/ker/" .. p1 .. ".s"

inc_tkh .sfunction p1, "os/tk/h/" .. p1 .. ".h"

inc_tks .sfunction p1, "os/tk/s/" .. p1 .. ".s"