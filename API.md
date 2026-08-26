# Knox Life — Modder API (API_VERSION 1)

**Knox Life** is the spawn and population framework under the Knox mods: baked
migration routes, a density-driven allocator, carrying-capacity population
dynamics, and the debug tooling to see what it did. Knox Life is the first
thing built on it, not the framework itself — the mod id is `KnoxLife` and the
Lua global is `KnoxLife`.

Species are plugins; the routes are the platform. The framework ships the route
budget, the allocator, the population model and the tooling; your addon ships a
species definition and, optionally, its own ground. The four wildlife species
register through this exact API — there is one code path, and you are on it.

If what you want to place isn't an animal — a faction, a camp, a patrol — skip
to [section 6](#6-building-something-thats-not-an-animal); `registerSpecies`
writes into Project Zomboid's animal system and won't serve you, but the
population model underneath is generic and public.

A complete species addon is about sixty lines of Lua. A fully commented one
lives in [`examples/KnoxLifeOpossum`](examples/KnoxLifeOpossum); a
shipping one with art is the
[fox addon](https://github.com/broroeror/knoxlife-fox).

---

## 1. The compatibility contract

**`require=KnoxLife` in your mod.info.** This makes your shared files load
after the base mod's, which is what makes everything below callable at your
file scope.

**The version gate**, verbatim at the top of every file that touches the API
(all five shipping addons carry it):

```lua
if not KnoxLife or (KnoxLife.API_VERSION or 0) < 1 then
    print("[MyAddon] needs Knox Life API_VERSION 1. Not loading.")
    return
end
local KW = KnoxLife
```

The Lua global is `KnoxLife`, and it is the only one. An earlier
`KnoxWildlife` alias was removed before first release rather than carried
forward: nothing had shipped, so there was no code to stay compatible with,
and two names for one table is a cost with no payer.

**Versioning policy:** `API_VERSION` moves only on breaking changes to the
functions documented here. Additive changes — new functions, new optional
fields — never bump it. Anything prefixed `_` or not on this page is internal
and may change without notice.

**The lifecycle.** Register at your file's top level (shared load). The base
mod applies registrations on `OnGameBoot` / `OnInitGlobalModData` /
`OnGameStart`, and hands routes to the engine on `OnLoadMapZones` — after
which the window is closed. There is no late-registration hook; a species
registered after world load is silently never placed.

**The side split.** Everything in sections 2–4 is shared and callable at file
scope. The spawn helpers in section 5 live **server-side**: they do not exist
during any shared file's load, and they are nil forever on a multiplayer
client. Feature-detect them (`if KW.reseedNear then`) rather than assuming the
version gate covers them — it does not.

---

## 2. Registering a species

### `KW.registerSpecies(id, def) -> boolean`

Validates, fills defaults, stores a copy, and returns `false` with a console
line instead of erroring. `id` is the migration-group name and must be unique —
probe with `KW.hasSpecies(id)` before claiming one.

```lua
KW.registerSpecies("kwc_fox", {
    female = "kwc_foxvixen",   -- REQUIRED: animal type names from
    male   = "kwc_foxdog",     --   AnimalDefinitions (your art mod defines
    baby   = "kwc_foxkit",     --   these; see section 6)
    possibleBreed = "default", -- REQUIRED: a nil breed crashes chunk loading,
                               --   so registration refuses it up front

    minAnimal = 1,             -- these two count FEMALES ONLY;
    maxAnimal = 2,             --   males and babies are added on top
    maxMale = 1,
    babyChance = 45,           -- percent

    density = 2.0,             -- animals per square mile, real-world figure.
                               --   Omit it and you get 2.0 plus a console
                               --   nudge to set a real number.

    habitat = "kwc_fox",       -- optional: the route pool this species walks
                               --   (yours, via registerRoutePool, or "deer",
                               --   "rabbit", "turkey", "raccoon"). Omit it and
                               --   the species inherits its bucket's ground.

    trackSize = "medium",      -- forage/tracking hints
    speed = 0.06,

    enabledOption = "MyMod.Enabled",  -- optional sandbox wiring, see section 4
    routeOption   = "MyMod.Routes",
    groupOption   = "MyMod.GroupSize",
})
```

### `KW.addToBucket(bucket, id, weight) -> boolean`

The mandatory second call — a registered species that is in no bucket never
spawns. `bucket` is `"large"` or `"small"`, nothing else. The bucket decides
the species' fallback ground when it has no `habitat` of its own.

```lua
KW.addToBucket("small", "kwc_fox", 50)
```

`weight` is written through as the engine-facing `chance` for bucket-typed map
zones; on the shipped map no such zones exist, so in practice your own routes
carry your animals — but supply a sane weight anyway.

Both calls together:

```lua
if KW.registerSpecies("kwc_fox", def) then
    KW.addToBucket("small", "kwc_fox", 50)
end
```

### Suppressing a species

`KW.removeFromBucket(bucket, id)` stops an **addon** species from spawning
while leaving it registered. It does **not** work on the base mod's four
species — their registration re-adds them on the first apply pass after your
file ran. There is currently no supported way to suppress a base species;
if you need one, open an issue and say so.

---

## 3. Shipping your own ground

### `KW.registerRoutePool(name, pool) -> boolean`

A pool is a non-empty list of routes, best habitat first:

```lua
KW.registerRoutePool("mymod_opossum", {
    { follow = { 2172,11200, 2146,11201, 2121,11206 },   -- flat x,y pairs,
      eat    = { 2172,11200, 2162,11202 },               --   world tile coords
      sleep  = { 2121,11206, 2117,11210 } },
    -- ... hundreds more
})
```

Rules the call enforces (rejection is loud and fail-closed):

- `follow` is a flat, even-length list of at least two `x,y` points;
- **every `eat` and `sleep` leg shares at least one exact vertex with its
  `follow` leg.** The engine joins zones by identical points, not proximity.
  A leg that never touches its follow line gets a null junction list, and the
  pathfinder dereferences it every tick — roughly a thousand
  NullPointerExceptions a minute, hours after registration looked fine. This
  used to be enforced only inside our private generator; as of API 1 the
  registration call checks it for you.

First registration wins on pool names, so prefix yours with your mod id.
Addon pools are *extra* ground — they do not take a share of the base mod's
route budget.

Pools are big. Generate them offline however you like (ours come from a
private tool that reads the game's biome maps), commit the generated Lua, and
feature-detect the call in that file:

```lua
if KnoxLife and KnoxLife.registerRoutePool then
    KnoxLife.registerRoutePool("mymod_opossum", MyMod.Routes)
end
```

A silent no-op beats a stack trace when someone runs your addon with the base
mod disabled.

---

## 4. Sandbox options

- `KW.getOption(name, fallback)` — reads the base mod's **KnoxLife**
  sandbox page.
- `KW.readOption(opt, fallback)` — the general form: a plain name reads the
  base page, a dotted `"Page.Key"` reads *your* page.
- `KW.settingsReady() -> boolean` — true once sandbox values exist. **Every
  option read silently returns its fallback before this is true**, and
  `enabledOption` fails *open* (species enabled) — design for that.

The three option names you gave `registerSpecies` do the wiring for you:
`enabledOption` gates placement, `routeOption` multiplies the species'
population, `groupOption` multiplies its group size. Put the options on the
shared **`KnoxLifeAnimals`** sandbox page (`page = KnoxLifeAnimals` in
your sandbox-options.txt) and they appear alongside every other species'.

One shape constraint: `routeOption` / `groupOption` values index the scale
table `{0.25, 0.5, 1.0, 1.5, 2.0}` — your sandbox enum must be **exactly five
positions with "Normal" third**, or the admin's slider quietly stops matching
its labels.

Respecting the world dials in your own code:

- `KW.realismFraction()` — the global density dial as a fraction of real 1993
  Kentucky; multiply any custom spawn math by it.
- `KW.groupScale()` / `KW.scaleCount(base, floor)` — the global group-size
  dial, with a floor so a half-size world never rounds a lone animal to zero.
- `KW.routeScaleFor(id)` / `KW.groupScaleFor(id)` — your per-species dials,
  resolved; `1.0` when unset.

Useful to know: **group size is population-neutral above the floor.** Routes
are computed as `density x habitat / meanGroupSize x dials`, so doubling group
size halves the group count. The exception is the `MIN_ROUTES = 20` per-species
floor: once a species pins there, the division stops cancelling.

---

## 5. Spawning and diagnostics (server-side)

These live in server Lua: nil during shared load, nil forever on MP clients.
On a client they either don't exist or safely do nothing — a zero return on a
client means "wrong side", not "no room".

- `KW.spawnOne(animalType, breed, x, y) -> boolean` — the single choke point
  every KW-spawned animal passes through. Carries the MP-client guard and the
  loaded-square check for you. `breed` is the **object**, not the string —
  get it from `KW.pickBreed(animalType, possibleBreed)`, and tolerate nil.
- `KW.spawnAnimalOf(species, x, y) -> boolean` — one individual by species id,
  female-biased 65/35, honouring live sandbox scaling.
- `KW.seedGroup(species, x, y) -> placedCount` — one full sandbox-scaled family
  group, scattered over a 9x9 around the point. Habitat-blind: it puts the
  group wherever you point.
- `KW.reseedNear(px, py, radius) -> placed, groups, skipped` — the admin entry
  point for installing into an existing world: seeds one group per unseeded
  registered route within radius, with per-route bookkeeping so repeat calls
  are safe. Radius is measured to each route's *midpoint*, so a long route
  passing under your feet can still be skipped.
- `KW.targetRoutes(id)`, `KW.meanGroupSize(id)`, `KW.allocateRoutes()` — the
  population math, readable. Two honest caveats: `meanGroupSize` reads the
  live engine table, so before the first apply pass it returns *unscaled
  vanilla* values for species vanilla ships (deer, rabbit) and 0 for everyone
  else; and a plan taken before sandbox values load is a valid *default-
  settings* plan, not the live one. Treat `KW.species` and the returned plan
  as read-only — the stored def **is** the live registry.

For everything else — the in-game population report, the locator, per-kill
logging — open the debug menu (`KnoxLife` on the MAIN tab) rather than
calling internals.

---

## 5b. The food chain

Two numbers put your species in it. Same shape as `density`: nothing is shared,
so nothing is stolen, and a bear that declares a threat is immediately something
every existing predator can reason about.

```lua
KW.setThreat("myaddon_bear", 12, 1.1)   -- threat, courage
KW.setThreat("myaddon_vole", 0.5)       -- no courage: never initiates
```

| | |
|---|---|
| `threat` | what you are worth in a fight. Summed on **both** sides. |
| `courage` | the advantage you need before you will **start** one. Omit it and your species is prey. |

The rule, entire:

```
attack if   sum(my side threat)  >=  sum(their side threat) * my courage
```

Threat is scaled at runtime by life stage (a baby counts about a third) and by
remaining health, so predators favour the wounded.

⚠️ **Do not give anything a `threat` for players or zombies.** Stage 2 is prey
only, deliberately — see STATUS 7j.

### Replacing how a bite is delivered

`KW.Predation.strike(predator, prey)` decides what a bite *looks like*;
everything else decides whether one happens. It is the seam a Java addon
overrides — with ZombieBuddy present you can gain a real attack animation
(STATUS 7h) and play it before calling through:

```lua
local prev                       -- ⚠️ declare on its own line
prev = KW.setStrikeHandler(function(pred, prey)
    playTheLunge(pred)
    return prev(pred, prey)      -- keep the damage, add the animation
end)
```

⚠️ `local prev = KW.setStrikeHandler(function() ... prev ... end)` looks the same
and is broken: a Lua local is only in scope *after* its own statement, so the
closure captures a nil `prev`, the call-through never happens, and your addon
silently does no damage while appearing to work.

`setStrikeHandler` returns the handler you replaced precisely so that chain is
possible. Return `true` from a strike when the prey died.

---

## 6. Building something that's not an animal

`registerSpecies` writes into `MigrationGroupDefinitions`, which is Project
Zomboid's **animal** system — so a faction, a camp, or anything spawned through
some other mechanism cannot register through it, and should not try.

What *is* reusable is the population model underneath, and it is deliberately
generic. If you have your own entities and your own way of placing them, these
four give you carrying-capacity simulation for free:

```lua
local KW = KnoxLife

local cx, cy = KW.cellOf(px, py)        -- world coords -> population cell
local k      = 12                        -- YOUR carrying capacity for this cell
local n      = countMyThingsIn(cx, cy)   -- YOUR census; KW's counts animals only

-- Logistic growth toward k, plus a small immigration term so a cell that hit
-- zero can still recover. Scaled by the admin's Recovery Rate setting.
local grown = KW.grow(n, k, hoursElapsed * KW.recoveryScale())
placeMyThings(grown - n)
```

| Call | What it gives you |
|---|---|
| `KW.CELL` | the grid size the whole model is expressed in (tiles) |
| `KW.cellOf(x, y) -> cx, cy` | world coordinates to population cell |
| `KW.grow(n, k, hours) -> n'` | logistic growth with an immigration term |
| `KW.recoveryScale() -> number` | the admin's Recovery Rate as a multiplier |

`KW.capacityIn(cx, cy)` and `KW.censusIn(cx, cy)` are also public, but both are
animal-specific: capacity is derived from KW's own registered species, and the
census counts what `cell:getAnimals()` returns. Supply your own for anything
else — that is usually a narrowing rather than an extension, because your thing
probably has one population where wildlife has eight.

Two constraints inherited from where this lives: it is **server-side** (nil
during shared load, nil on a multiplayer client), and it is only meaningful once
the world is up.

If you want the habitat scoring as well — "where in this forest would something
actually live" — that is baked offline into route data rather than computed at
runtime. Ship your own pools through `registerRoutePool` (section 3) and the
same machinery places them.

---

## 7. The part the API cannot do for you: the animal

`registerSpecies` places and moves animals; it does not create them. Your
`female` / `male` / `baby` names must exist in `AnimalDefinitions`, which means
your addon ships art (a `.glb` on a vanilla skeleton, so the game's own
animation sets drive it) and a definitions file that copies a vanilla donor and
overrides what differs. The
[fox addon](https://github.com/broroeror/knoxlife-fox) is the reference:
`KWC_FoxDefinitions.lua` copies the vanilla raccoon, and `wild = true` /
`canBeDomesticated = false` are load-bearing. Cleaning up that recipe into a
first-class helper is on the roadmap; until then, copy the fox.

---

## Sharp edges, collected

- Register at file scope; the window closes at world load.
- Spawn helpers are server-side; feature-detect, don't version-gate.
- Option reads return fallbacks (and enabled-gates fail open) until
  `KW.settingsReady()`.
- `minAnimal`/`maxAnimal` count females only.
- Route legs must share exact vertices (validated at registration since API 1).
- Per-species option enums: five positions, Normal third.
- A species in both buckets is planned twice — pick one.
- `MIN_ROUTES = 20` pins rare species; below ~0.3 combined multiplier the
  dials stop responding.
- Base species cannot be suppressed yet; addon species can
  (`removeFromBucket`).

Found an edge that isn't listed? That's a bug in the docs — open an issue.
