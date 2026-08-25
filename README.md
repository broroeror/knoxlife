# KnoxLife

Wild-animal spawning for Project Zomboid (build 42), tuned to 1990s rural
Kentucky: many small family groups spread across the map, instead of a few
enormous herds.

The vanilla map ships only 20 migration routes, so its animals pile into a
handful of oversized herds you either trip over or never find. KnoxLife
bakes hundreds of routes from the game's own biome maps and places each species
at its actual recorded 1993 density — about a thousand deer at 11.4 per square
mile, roughly 890 raccoons, turkey flocks at the peak of Kentucky's restoration
— in groups the size of real families.

## What it does

- **Realistic populations.** Each species carries its real-world density and the
  map's habitat decides how many groups that makes. One dial scales the whole
  world from a quarter of realistic to double.
- **Wild turkeys and raccoons.** The game ships complete art for both and never
  spawns either; this turns them loose.
- **Recovery.** Vanilla spawns each area's animals exactly once, so a valley you
  hunt out stays empty forever. With recovery on, survivors slowly breed back —
  never past what the habitat supports.
- **Farm rebalance.** Cattle on roughly half of farms in real cow-calf herds,
  sheep genuinely rare, the way 1990s Kentucky actually looked.
- **Admin and testing tools.** A right-click locator that points at the nearest
  animal of any species, and a KnoxLife section in the debug menu with a
  population report of what actually got placed.

## The family

| Mod | What it adds |
|---|---|
| **KnoxLife** (this repo) | the framework, densities, recovery, farms, turkeys, raccoons |
| [KnoxLife: Foxes](https://github.com/broroeror/knoxlife-fox) | red fox — farm edge and fencerow |
| [KnoxLife: Coyotes](https://github.com/broroeror/knoxlife-coyote) | coyote — wide-ranging edge hunter |
| [KnoxLife: Bobcats](https://github.com/broroeror/knoxlife-bobcat) | bobcat — deep cover and forest interior |
| [KnoxLife: Squirrels](https://github.com/broroeror/knoxlife-squirrel) | grey squirrel — mature hardwood |
| [KnoxLife: Overkill](https://github.com/broroeror/knoxlife-overkill) | overkill ruins the carcass |

Each addon needs this mod and nothing else. Disable one and its animals simply
are not placed; nothing shifts to compensate, because every species has its own
target.

## Sandbox settings

Three pages under Sandbox Options:

- **KnoxLife** — the world dials: density, species mix, group size,
  recovery, farms, admin tools.
- **KnoxLife: Animals** — every species, each with an enable toggle, a
  number-of-groups multiplier, and an animals-per-group multiplier. Addon
  species appear here automatically.
- **KnoxLife: Overkill** — if that addon is installed.

One relationship worth knowing: **group size does not change how many animals
exist.** The group count is worked out by dividing the population by the group
size, so bigger groups just means fewer, rarer groups holding the same total.
Only density, species mix, and a species' own number-of-groups actually move
the population.

## Adding your own species

This mod is built on **Knox Life** (mod id `KnoxLife`) — the spawn and
population framework that ships inside it: baked migration routes, a
density-driven allocator, and carrying-capacity population dynamics. It is
documented and open for anyone to build on, wildlife or otherwise.

A complete species addon is about sixty lines of Lua — no route data, no map
analysis, no generator. If what you want to spawn isn't an animal, the
population model is generic and public. **[API.md](API.md)** documents the whole
contract; a fully commented example lives in
[examples/KnoxLifeOpossum](examples/KnoxLifeOpossum).

## Installing

A Workshop release is coming. Until then, clone or download this repository
into your `Zomboid/mods/` folder and enable it in-game as usual.

## Credits

Built on Project Zomboid by The Indie Stone. Nothing from the base game is
redistributed — the mod references vanilla assets by name and ships only its
own files.

## Licence

Code is [MIT](LICENSE). Art — models, textures, sounds, the icon and poster —
is under the friendlier-but-firmer terms in [ASSETS-LICENSE.md](ASSETS-LICENSE.md):
use it in your own PZ mods with credit, just don't resell it or reupload the mod
wholesale.
