> [!NOTE]
> This plugin is from the future and cannot be used yet

# [NMRiH] Breakable Weapons
Adds durability to melee weapons, causing them to break after prolonged use.

Anything that imposes a stamina penalty also causes the weapon to wear down.

![image](https://github.com/dysphie/nmrih-breakable-weapons/assets/11559683/cde38476-7c6a-493c-9fa1-c8869ce83f6e)


## Requirements
- Sourcemod
- No More Room in Hell 1.13.5 or higher

## ConVars 
| Variable | Description | Default value |
| --- | --- | --- |
| sm_breakable_melee_default_durability | Default durability applied to weapons not found in the config file. -1 = unbreakable | -1 | 
| sm_breakable_melee_sound | Sound to play upon melee weapon breakage | physics/wood/wood_plank_break8.wav |

## Settings

Edit melee durability in `configs/breakable-melee.cfg`. The value represents the number of hits before the weapon breaks.

```cpp
"Durabilities"
{
    me_axe_fire 1000 // Makes the fire axe break after a thousand hits
}
```
