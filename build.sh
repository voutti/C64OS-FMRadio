#!/bin/bash

#COMPILER=/c/users/timo.voutilainen/apps/64tass-1.60.3243/64tass.exe
COMPILER=64tass
ASCII2PETSCII="python ../ascii2petscii.py"
PETSCII2ASCII="python ../petscii2ascii.py"
D64IMAGE="bundle.d64"
IDE64HDD_IMAGE="./vice/c64os_ide64_c64os_1_09.hdd"

$COMPILER -I ./ -a main.asm -o main.o || exit 1
$ASCII2PETSCII about.ascii about.t || exit 1
$ASCII2PETSCII menu.ascii menu.m || exit 1

rm -f $D64IMAGE
c1541 -format test,id d64 $D64IMAGE || exit
c1541 -attach $D64IMAGE -write main.o main.o,prg || exit
c1541 -attach $D64IMAGE -write about.t about.t,seq || exit
c1541 -attach $D64IMAGE -write icon.charset icon.charset,seq || exit
c1541 -attach $D64IMAGE -write menu.m menu.m,seq || exit

echo "SUCCESS !!"
#exit 0

sync
umount ./vice/mymount || true
mkdir ./vice/mymount || true
cfs011mount $IDE64HDD_IMAGE ./vice/mymount || exit
echo "Mounted $IDE64HDD_IMAGE"

#VICE needs correct permissions for files
chmod 755 ./main.o ./about.t ./icon.charset ./menu.m
rm -f ./vice/mymount/01\ c64\ os/os/applications/MyTest/*.*
cp ./main.o ./vice/mymount/01\ c64\ os/os/applications/MyTest/main.o,prg
cp ./about.t ./vice/mymount/01\ c64\ os/os/applications/MyTest/about.t,seq
cp ./icon.charset ./vice/mymount/01\ c64\ os/os/applications/MyTest/icon.charset,seq
cp ./menu.m ./vice/mymount/01\ c64\ os/os/applications/MyTest/menu.m,seq
sync

# Uncomment if you need local copy also
rm -f ./temp/mytest/*.*
cp ./main.o ./temp/mytest/main.o,prg
cp ./about.t ./temp/mytest/about.t,seq
cp ./icon.charset ./temp/mytest/icon.charset,seq
cp ./menu.m ./temp/mytest/menu.m,seq
sync

#x64sc -IDE64image1 "./vice/c64os_ide64.hdd" ./vice/vice-snapshot-c64os_1.vsf -mouse
# No need for -cartcrt, for example, if that is already included in the snapshot - just take more time in startup
x64sc -cartcrt "./vice/idedos20190819-c64.crt" -IDE64image1 $IDE64HDD_IMAGE
umount ./vice/mymount || true
echo "Unmounted $IDE64HDD_IMAGE"







