# C64OS-FMRadio
RDA5807 -based FM Radio app for C64 OS.
Requires radio IC connected via I2C to pins which C64OS supports for I2c.
Default is SDA: PB2/E, SCL: PB3/F on userport.

![image](https://github.com/voutti/C64OS-FMRadio/blob/master/images/FMRadioApp.jpg)

## C64 OS include files

This project does not vendor the full c64os-dev repository.

- Only `include/v1.09/os` is fetched when needed.
- Fetch is handled by `scripts/sync-c64os-os.sh`.
- The local override is reapplied from `overrides/c64os/v1.09/os/h/modules.h`.

`build.sh` only runs the fetch when `os/` is missing, so normal builds work offline once `os/` exists locally.
