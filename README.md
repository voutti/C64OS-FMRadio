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

## Radio Transaction Scheduling

Radio button and preset actions are queued with their widget pointers and
executed in FIFO order by the draw-phase dispatcher. Each complete action,
including read-modify-write sequences and tune/seek waits, finishes before
another action or status poll starts. Timer messages only request polling;
pending polls are coalesced and serviced after queued actions.

Before each queued action, the dispatcher saves the radio state. If any I2C
step fails, it restores that state and redraws the controls, including any
checkboxes or preset radios already toggled by Toolkit. The communication error
is shown on the log line, and scan actions stop at the first failed step.
Successful actions retain their new state. This is a UI rollback, not a hardware
rollback: writes completed before a later failure may already have changed the
tuner.

The queue holds 15 pending actions. Additional actions are rejected with a
"Radio action queue full" status message. A busy guard prevents nested draw
callbacks from entering the dispatcher. This scheduling applies to both tuners;
it does not disable interrupts or protect against other software using the bus.

## Channel Monitoring

Settings > Monitor channel toggles periodic RSSI, stereo, and station-lock
monitoring. It starts enabled on each launch, with a native menu checkmark.
Toggling it shows "Monitor On" or "Monitor Off" on the log line. While disabled,
the last monitored values remain displayed and radio controls still work.
The application timer keeps running so log messages still clear automatically
after approximately 20 seconds. Only periodic radio reads are disabled.
The setting is not saved to the configuration file.
