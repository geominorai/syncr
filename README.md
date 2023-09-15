# SyncR

**SyncR** is a server-side SourceMod plugin for Team Fortress 2 jump servers designed to assist with rocket syncs.

Learning and executing syncs can be tremendously difficult due to lack of rocket visibility while aiming and due to latency effects of the remote server. To mitigate these, the player must adjust the timing but the learning process will be inconsistent and difficult.

This plugin provides three visual and one audio feedback mechanisms to help with learning:

### Visual
- Rocket time-to-impact is visualized via a colored laser emitted in front of the rocket (green to yellow to red).
- Player body overlapping with an existing rocket changes the laser to blue, i.e. for triple syncs (cyan to blue).
- Crit rocket particles are attached to rockets launched in sufficiently close bundles.
- Player predicted landing positions are visualized as a ring on the ground.
- Player landing and rocket impact distances are vizualized on the HUD with a chart.

### Audio
- Firing a rocket in a tight bundle with an existing rocket plays a crit rocket sound accompanying the crit particle effects.  Test trials indicate this feedback to be very satisfying for some learning players.

## Demonstration videos
[![YouTube video](https://img.youtube.com/vi/wqNsQ-erCd4/0.jpg)](https://www.youtube.com/watch?v=wqNsQ-erCd4)
[![YouTube video](https://img.youtube.com/vi/zVh711KY-h4/0.jpg)](https://www.youtube.com/watch?v=zVh711KY-h4)

## Usage
**SyncR** can be toggled by a player using `/syncr`, while admins with the `slay` flag can toggle for a player using `/setsyncr <name>`.

## Server ConVars:
```
syncr_laser [0/1]         - Show colored laser pointer
syncr_laser_all [0/1]     - Show colored laser pointer of all players using SyncR
syncr_laser_hide [0/1]    - Hides laser pointers when looking up
syncr_chart [0/1]         - Show distance to impact chart
syncr_ring [0/1]          - Show landing prediction ring
syncr_crit [0/1]          - Show sync crit particle
syncr_sound [0/1]         - Play sync crit sound
syncr_rave [0/1]          - Toggles disco/rave lasers for bored admins

syncr_warn_distance [Default: 440.0]   - Imminent rocket impact distance to warn with red
syncr_threshold [Default: 30.0]        - Distance required between rockets for crit feedback -- Set to 0 to disable
```

## Dependencies
* [SourceMod](https://www.sourcemod.net/) (1.12.0.7038 or newer)
* [SMLib](https://github.com/bcserv/smlib/tree/transitional_syntax)
