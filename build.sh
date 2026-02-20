#tmpx -i main.asm -o main.o
#COMPILER=/c/users/timo.voutilainen/apps/64tass-1.60.3243/64tass.exe
COMPILER=64tass
ASCII2PETSCII="python ../ascii2petscii.py"
PETSCII2ASCII="python ../petscii2ascii.py"
D64IMAGE="bundle.d64"

$COMPILER -a main.asm -o main.o || exit 1
$ASCII2PETSCII about.ascii about.t || exit 1
$ASCII2PETSCII menu.ascii menu.m || exit 1

rm -f $D64IMAGE
c1541 -format test,id d64 $D64IMAGE || exit
c1541 -attach $D64IMAGE -write main.o main.o,prg || exit
c1541 -attach $D64IMAGE -write about.t about.t,seq || exit
c1541 -attach $D64IMAGE -write icon.charset icon.charset,seq || exit
c1541 -attach $D64IMAGE -write menu.m menu.m,seq || exit

echo "SUCCESS !!"







