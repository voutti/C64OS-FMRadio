#!/bin/bash

set -e

COMPILER=64tass
ASCII2PETSCII="python ../ascii2petscii.py"
PETSCII2ASCII="python ../petscii2ascii.py"
IDE64HDD_IMAGE="./vice/c64os_ide64_c64os_1_09.hdd"
C64OS_VERSION="1.09"
CHIP="rda5807"
PACKAGE_ONLY=0
NO_RUN=0

usage() {
	echo "Usage: ./build.sh [rda5807|tea5767] [--package-only] [--no-run]"
	echo "  rda5807|tea5767  Select tuner target (default: rda5807)"
	echo "  --package-only    Build + create bundle outputs only (skip IDE64 deploy and VICE)"
	echo "  --no-run          Build + deploy to IDE64, but skip launching VICE"
}

for arg in "$@"; do
	case "$arg" in
		rda5807|tea5767)
			CHIP="$arg"
			;;
		--package-only)
			PACKAGE_ONLY=1
			NO_RUN=1
			;;
		--no-run)
			NO_RUN=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $arg"
			usage
			exit 1
			;;
	esac
done

case "$CHIP" in
	rda5807)
		APP_MAIN="main.asm"
		CHIP_DEFINE="-DCHIP_TEA=0"
		ABOUT_ASCII="about.ascii"
		OUT_DIR="./bundles/rda5807"
		BUILD_DIR="${OUT_DIR}/build"
		APP_DIR="MyTest"
		;;
	tea5767)
		APP_MAIN="main.asm"
		CHIP_DEFINE="-DCHIP_TEA=1"
		ABOUT_ASCII="about_tea.ascii"
		OUT_DIR="./bundles/tea5767"
		BUILD_DIR="${OUT_DIR}/build"
		APP_DIR="MyTest-TEA5767"
		;;
	*)
		echo "Unknown chip target: $CHIP"
		usage
		exit 1
		;;
esac

OBJ_FILE="${BUILD_DIR}/main.o"
ABOUT_PET="${BUILD_DIR}/about.t"
MENU_PET="${BUILD_DIR}/menu.m"
D64IMAGE="${BUILD_DIR}/bundle.d64"

mkdir -p "$BUILD_DIR"

# Keep local os/ available for offline builds. Only sync when os/ is missing.
if [[ ! -d "./os" ]]; then
	./scripts/sync-c64os-os.sh "$C64OS_VERSION"
fi

$COMPILER -I ./ -DTASM64=1 -DTMPASM=0 $CHIP_DEFINE -a "$APP_MAIN" -o "$OBJ_FILE"
$ASCII2PETSCII "$ABOUT_ASCII" "$ABOUT_PET"
$ASCII2PETSCII menu.ascii "$MENU_PET"

rm -f $D64IMAGE
c1541 -format test,id d64 $D64IMAGE
c1541 -attach $D64IMAGE -write "$OBJ_FILE" main.o,prg
c1541 -attach $D64IMAGE -write "$ABOUT_PET" about.t,seq
c1541 -attach $D64IMAGE -write icon.charset icon.charset,seq
c1541 -attach $D64IMAGE -write "$MENU_PET" menu.m,seq

echo "SUCCESS ($CHIP) !!"

# Local bundle artifacts per chip
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.*
cp "$OBJ_FILE" "$OUT_DIR/main.o,prg"
cp "$ABOUT_PET" "$OUT_DIR/about.t,seq"
cp ./icon.charset "$OUT_DIR/icon.charset,seq"
cp "$MENU_PET" "$OUT_DIR/menu.m,seq"
cp "$D64IMAGE" "$OUT_DIR/bundle.d64"
sync

if [[ "$PACKAGE_ONLY" == "1" ]]; then
	echo "Package-only mode: skipped IDE64 deploy and VICE launch"
	exit 0
fi

sync
umount ./vice/mymount || true
mkdir -p ./vice/mymount
cfs011mount $IDE64HDD_IMAGE ./vice/mymount || exit
echo "Mounted $IDE64HDD_IMAGE"

#VICE needs correct permissions for files
chmod 755 "$OBJ_FILE" "$ABOUT_PET" ./icon.charset "$MENU_PET"
mkdir -p "./vice/mymount/01 c64 os/os/applications/${APP_DIR}"
rm -f "./vice/mymount/01 c64 os/os/applications/${APP_DIR}"/*.*
cp "$OBJ_FILE" "./vice/mymount/01 c64 os/os/applications/${APP_DIR}/main.o,prg"
cp "$ABOUT_PET" "./vice/mymount/01 c64 os/os/applications/${APP_DIR}/about.t,seq"
cp ./icon.charset "./vice/mymount/01 c64 os/os/applications/${APP_DIR}/icon.charset,seq"
cp "$MENU_PET" "./vice/mymount/01 c64 os/os/applications/${APP_DIR}/menu.m,seq"
sync

if [[ "$NO_RUN" == "1" ]]; then
	umount ./vice/mymount || true
	echo "No-run mode: skipped VICE launch"
	exit 0
fi

#x64sc -IDE64image1 "./vice/c64os_ide64.hdd" ./vice/vice-snapshot-c64os_1.vsf -mouse
# No need for -cartcrt, for example, if that is already included in the snapshot - just take more time in startup
x64sc -cartcrt "./vice/idedos20190819-c64.crt" -IDE64image1 $IDE64HDD_IMAGE
umount ./vice/mymount || true
echo "Unmounted $IDE64HDD_IMAGE"







