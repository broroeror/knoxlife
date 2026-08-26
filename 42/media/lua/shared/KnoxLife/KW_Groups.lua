-- Knox Life -- migration groups.
--
-- A migration group is one family unit that walks a route. minAnimal/maxAnimal
-- count FEMALES only; males and babies are added on top of that range, which is
-- easy to misread and is how a "max 5" deer group becomes eleven animals.
--
-- This file no longer owns the species list. It registers the four the base mod
-- ships through the same public API an addon uses (see KW_Core.lua), then
-- applies whatever is in the registry -- base species and addon species alike,
-- by exactly the same code path. If it works for a coyote addon it works for
-- vanilla deer, because there is only one path.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

-- Timings and trace chances shared by every group unless it overrides them.
-- These are the vanilla deer values; they read as "a wild animal that eats,
-- beds down and leaves sign", and nothing about them is species-specific
-- enough to be worth diverging by default.
local COMMON = {
    minTimeBeforeSleep = 1500,
    maxTimeBeforeSleep = 1900,
    minTimeBeforeEat = 1200,
    maxTimeBeforeEat = 1800,
    timeToEat = 100,
    timeToSleep = 60,
    trackChance = 8000,
    poopChance = 10500,
    brokenTwigsChance = 8000,
    herbGrazeChance = 5000,
    furChance = 5000,
    flatHerbChance = 5000,
}

-- The species the base mod ships. Turkey and raccoon are here because the game
-- already contains complete art for both -- mesh, skeleton, animation clips and
-- sounds -- and simply never spawns them in the world.
local function registerCoreSpecies()
    if KW._coreSpeciesRegistered then return end
    KW._coreSpeciesRegistered = true

    KW.registerSpecies("deer", {
        density = 11.4,   -- animals per sq mi. 450,000 in Kentucky in 1993 over 39,486 sq mi
        female = "doe", male = "buck", baby = "fawn",
        minAnimal = 2, maxAnimal = 5, maxMale = 1, babyChance = 20,
        possibleBreed = "whitetailed",
        trackSize = "large", speed = 0.07,
        habitat = "deer",
        routeOption = "DeerRoutes", groupOption = "DeerGroupSize",
    })
    -- ⚠️ THIS IS THE ONE PLACE THE MOD DEPARTS FROM VANILLA'S FAMILY SIZES, and
    -- it is deliberate. Vanilla gives rabbits 3-8 does plus 3 bucks: a mean of
    -- 9.2 and a worst case of 19, the largest group in the game. Reported from
    -- play as a wall of rabbits, and it is warren behaviour.
    --
    -- Eastern cottontails do not live in warrens. That is Oryctolagus cuniculus,
    -- the European rabbit, a different genus. A cottontail doe raises a litter in
    -- a shallow surface nest and the young disperse at four to five weeks; adults
    -- are solitary. They reach three to five per acre in good cover, which is a
    -- great many rabbits and still not a herd: the abundance is many animals
    -- sharing habitat, not one family walking about together.
    --
    -- So the group shrinks and the WEIGHT rises to compensate, which the weight
    -- formula does by itself: it is proportional to sqrt(density / group size),
    -- so a third of the group size raises the weight from 100 to 167. Rabbits
    -- stay the most numerous animal on the map and stop arriving in heaps.
    --
    -- BREEDS: the Appalachian cottontail is dropped. Kentucky has three rabbit
    -- species and only the eastern cottontail is statewide; the Appalachian is a
    -- Cumberland Plateau animal reaching west only to about Lincoln and Boyle
    -- counties, and this map is the Ohio River at Muldraugh, well west of that
    -- and at the wrong elevation. The swamp rabbit stays: it is a real Kentucky
    -- species and it suits the water the routes already favour.
    KW.registerSpecies("rabbit", {
        -- 3-5 per acre in good cover biologically, and this declared 64 on that
        -- basis. But the rabbit pool holds 428 routes and 64 asked for 1,723,
        -- so rabbits sat pinned at the ceiling on every one of the five density
        -- settings -- the dial moved nothing, in either direction, ever, and
        -- the planner reported a conflict at the mod's own defaults.
        --
        -- 15.8 is what the shipped pool delivers: 428 routes x 3.3 per group
        -- / 88.83 sq mi = 15.9, set a shade under so Realistic clears without
        -- a warning. DELIVERABLE, not biological -- see the squirrel's note in
        -- KnoxLifeSquirrels/Squirrel_Species.lua for the full reasoning.
        density = 15.8,
        female = "rabdoe", male = "rabbuck", baby = "rabkitten",
        minAnimal = 1, maxAnimal = 3, maxMale = 1, babyChance = 40,
        possibleBreed = "swamp,cottontail",
        trackSize = "small", speed = 0.03,
        habitat = "rabbit",
        routeOption = "RabbitRoutes", groupOption = "RabbitGroupSize",
    })
    -- Real eastern wild turkey flocks run roughly 5-20 birds outside the
    -- spring breakup.
    KW.registerSpecies("turkey", {
        density = 1.3,   -- animals per sq mi. about 50,000 in 1993, interpolated 20,000 (1989) to
        -- 130,000 (1997)
        female = "turkeyhen", male = "gobblers", baby = "turkeypoult",
        minAnimal = 4, maxAnimal = 11, maxMale = 2, babyChance = 45,
        possibleBreed = "meleagris",
        trackSize = "small", speed = 0.035,
        enabledOption = "WildTurkey",
        habitat = "turkey",
        routeOption = "TurkeyRoutes", groupOption = "TurkeyGroupSize",
    })
    -- Deliberately tiny: raccoons are near-solitary, and a "group" is really
    -- one sow with her kits, occasionally a boar nearby.
    KW.registerSpecies("raccoon", {
        density = 10.0,   -- animals per sq mi. order of magnitude: 5.2/km2 bottomland, 1.6/km2 upland
        female = "raccoonsow", male = "raccoonboar", baby = "raccoonkit",
        minAnimal = 1, maxAnimal = 2, maxMale = 1, babyChance = 60,
        possibleBreed = "grey",
        trackSize = "small", speed = 0.04,
        enabledOption = "WildRaccoon",
        habitat = "raccoon",
        routeOption = "RaccoonRoutes", groupOption = "RaccoonGroupSize",
    })

    -- WEIGHTS ARE DERIVED FROM POPULATION, AND THE UNIT IS GROUPS PER AREA, NOT
    -- ANIMALS. One route is one family unit, so a species that flocks needs
    -- fewer routes than a solitary one at the same population. Turkeys move in
    -- 4-11 birds and raccoons in 1-2, which is nearly an order of magnitude.
    --
    --   weight  proportional to  sqrt( density per sq mi / mean group size )
    --
    -- The sources are uneven and it is worth being honest about which is which.
    -- Kentucky held about 450,000 deer in 1993 and about 50,000 turkeys,
    -- interpolated from 20,000 in 1989 to 130,000 in 1997. For rabbit and
    -- raccoon NO statewide estimate exists: Kentucky Fish and Wildlife state
    -- plainly that no population estimate can be derived from the Mail Carrier
    -- Survey, so those two come from published per-area densities and are
    -- order-of-magnitude only.
    --
    --   species   /sq mi   group   groups   weight
    --   rabbit      ~64      ~3.3   19.4      167
    --   raccoon     ~10      ~2.5    4.0       71
    --   deer        ~11.4    ~4.7    2.4       55
    --   turkey      ~1.3     ~9      0.14      13
    --
    -- Rabbit reads 167 rather than 100 because its group shrank; the formula did
    -- that on its own, which is the point of deriving weights rather than picking
    -- them. Scale is set by whichever species you like: they are all one ruler.
    --
    -- The square root is a deliberate liberty for playability. Taken linearly,
    -- turkey lands at 2% of small-game routes, which is faithful to 1993 and
    -- makes the bird a ghost the player never meets. It also contradicts the
    -- restoration story: 1993 should read as common and climbing.
    --
    -- WEIGHTS ARE NOW GLOBAL, not relative within a bucket, because there is one
    -- route budget for the whole map. Deer sit at 55 against rabbit's 100
    -- because that is what the population says; the Species Mix sandbox option
    -- multiplies the deer weight (1.0 realistic, 2.0 balanced, 3.3 deer
    -- country) rather than the bucket structure doing it invisibly.
    --
    -- A bucket now decides ONE thing: which route pool a species falls back to
    -- when it declares no habitat. `large` means deer ground, `small` means
    -- rabbit ground. `addToBucket` is unchanged for addons.
    KW.addToBucket("large", "deer", 55)
    -- 167, not 100, and it is the same formula rather than a thumb on the scale:
    -- weight is proportional to sqrt(density / mean group size), so cutting the
    -- rabbit group from 9.2 animals to 3.3 raises it by itself. Rabbits are still
    -- by far the most numerous animal on the map; they simply arrive in ones and
    -- twos now. Capped where it is because the map's rabbit habitat is finite:
    -- see the pool ceiling note in KW_Core.
    KW.addToBucket("small", "rabbit", 167)
    KW.addToBucket("small", "raccoon", 71)
    KW.addToBucket("small", "turkey", 13)
end

-- Lives in KW_Core now, because the route allocator has to ask the same
-- question: a species switched off in sandbox must not consume route budget
-- that the enabled ones could have used.
local speciesEnabled = KW.speciesEnabled

local function applySpecies(id, def)
    MigrationGroupDefinitions[id] = MigrationGroupDefinitions[id] or {}
    local g = MigrationGroupDefinitions[id]

    g.female = def.female
    g.male = def.male
    g.baby = def.baby
    g.possibleBreed = def.possibleBreed
    g.trackSize = def.trackSize
    g.speed = def.speed

    -- Scale the family, then keep the invariants the spawner assumes:
    -- max >= min, and never more males than females.
    -- Global Group Size, then this species' own multiplier, so an admin can
    -- thin the rabbits without touching the deer.
    g.minAnimal, g.maxAnimal, g.maxMale = KW.scaledGroupOf(id, def)

    g.babyChance = def.babyChance

    for k, v in pairs(COMMON) do g[k] = v end
    if def.timing then
        for k, v in pairs(def.timing) do g[k] = v end
    end
end

local function applyBucket(bucket)
    MigrationGroupDefinitions[bucket] = MigrationGroupDefinitions[bucket] or {}
    local b = MigrationGroupDefinitions[bucket]
    b.groups = b.groups or {}

    for id, weight in pairs(KW.buckets[bucket] or {}) do
        local def = KW.species[id]
        if def and speciesEnabled(def) then
            b.groups[id] = b.groups[id] or {}
            b.groups[id].animal = id
            b.groups[id].chance = weight
        else
            -- A species switched off in sandbox, or listed in a bucket without
            -- ever being registered, must not stay in the pool: the spawner
            -- would pick a group that does not exist.
            b.groups[id] = nil
        end
    end
end

function KW.applyGroups()
    if not MigrationGroupDefinitions then
        KW.log("migration definitions not loaded yet; deferring")
        return false
    end

    KW.warnAboutConflicts()
    registerCoreSpecies()

    local applied, skipped = 0, 0
    for id, def in pairs(KW.species) do
        if speciesEnabled(def) then
            applySpecies(id, def)
            applied = applied + 1
        else
            skipped = skipped + 1
        end
    end

    applyBucket("large")
    applyBucket("small")

    local d = MigrationGroupDefinitions.deer
    KW.logChange("groups", string.format(
        "%d species applied%s -- deer %d-%d does + %d buck",
        applied,
        skipped > 0 and (" (" .. skipped .. " disabled)") or "",
        d.minAnimal, d.maxAnimal, d.maxMale))
    return true
end

-- Apply once at load for singleplayer sanity, then again once the sandbox
-- settings actually exist, since group sizes depend on them. Addons registering
-- at their own file scope land before the event-driven applies, so their
-- species are picked up without needing to hook anything themselves.
KW.applyGroups()

if Events then
    if Events.OnGameBoot then Events.OnGameBoot.Add(KW.applyGroups) end
    if Events.OnInitGlobalModData then Events.OnInitGlobalModData.Add(KW.applyGroups) end
    if Events.OnGameStart then Events.OnGameStart.Add(KW.applyGroups) end
end
