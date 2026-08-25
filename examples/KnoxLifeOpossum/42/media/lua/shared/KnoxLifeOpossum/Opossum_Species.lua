-- Knox Life: Opossums -- example addon for the Knox Life API.
--
-- This is the whole addon. There is no route data, no generator, no map
-- analysis: the base mod owns hundreds of migration routes across the map, and
-- a species registered into a bucket inherits its share of them.
--
-- What a real version of this still needs is ART. Opossum has no model in the
-- game, so `possibleBreed` and the animal type names below refer to definitions
-- that do not exist yet. The four shipping addons (fox, coyote, bobcat,
-- squirrel) are working references: each is a new mesh rigged onto a vanilla
-- animal skeleton, keeping the donor's clip names, exported as a single .glb.

-- Fail politely rather than erroring if the framework is missing or too old.
-- mod.info's `require=KnoxLife` should prevent this, but a user can always
-- disable the base mod and leave the addon enabled.
if not KnoxLife or (KnoxLife.API_VERSION or 0) < 1 then
    print("[KnoxLifeOpossum] Knox Life not found (or too old); "
        .. "this addon needs API_VERSION 1. Not loading.")
    return
end

local KW = KnoxLife

KW.registerSpecies("opossum", {
    -- Animal type names, as defined in AnimalDefinitions. Your art mod supplies
    -- these; the names here are what you would call them.
    female = "opossumfemale",
    male = "opossummale",
    baby = "opossumjoey",

    -- Required. A nil breed crashes animal chunk loading, so registerSpecies
    -- refuses the registration rather than letting it fail later.
    possibleBreed = "virginia",

    -- Opossums are solitary; a "group" here is one animal, or a female with
    -- joeys riding along. minAnimal/maxAnimal count FEMALES; the male and
    -- babies are added on top.
    minAnimal = 1,
    maxAnimal = 1,
    maxMale = 1,
    babyChance = 60,

    trackSize = "small",
    speed = 0.04,          -- they amble; nothing about an opossum hurries

    -- Optional. Which baked route pool this species walks: "deer", "rabbit",
    -- "turkey" or "raccoon". Leave it out and the species inherits its bucket's
    -- pool, which is what every addon written before this field existed gets.
    --
    -- Pick the ground the animal lives on rather than the one it looks like it
    -- belongs to. An opossum is a bottomland and streamside forager, exactly
    -- the raccoon's ground, so it borrows the raccoon routes.
    habitat = "raccoon",

    -- Real-world animals per square mile; the base mod turns this into route
    -- counts against the map's habitat. Opossums were genuinely abundant.
    density = 6.0,

    -- Optional: wire it to a sandbox toggle of your own.
    -- enabledOption = "WildOpossum",
})

-- Weight is relative within the bucket, where rabbit is 100. Abundant animal,
-- modest share: opossums are common but the bucket is crowded.
KW.addToBucket("small", "opossum", 25)

print("[KnoxLifeOpossum] registered opossum (API v" .. KW.API_VERSION .. ")")
