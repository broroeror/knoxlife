-- Knox Life -- farm livestock.
--
-- Vanilla weights a random farm's livestock like this:
--     chicken 60 | sheep 21 | pig 16 | turkey 15 | rabbit 10 | cow 6
-- which makes a farm three and a half times more likely to hold sheep than
-- cattle. Kentucky was the largest beef state east of the Mississippi. The 1992
-- Census of Agriculture counted 42,898 farms running beef cows against 1,032
-- farms running sheep -- a ratio of roughly forty to one, the other way round.
--
-- We do not push it all the way to forty to one, because a farm type that shows
-- up on one map farm in a hundred may as well not exist. Eleven to one puts
-- cattle where they belong while leaving sheep as a real but uncommon find.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

-- chance is a weight, not a percentage: the game sums every entry and rolls
-- across the total, so these only matter relative to each other.
local WEIGHTS = {
    cow = 20, cowlarge = 24,                                  -- 44  the backbone
    chicken = 16, chickensmall = 16, chickenbig = 8,          -- 40  backyard flocks
    pig = 8, pigsmall = 6, piglarge = 4, pigonlyone = 2,      -- 20  common, declining
    rabbit = 4, rabbitsmall = 2,                              --  6  hutch hobby
    sheep = 2, sheepsmall = 1, sheeplarge = 1,                --  4  ~1% of farms
    turkey = 2, turkeysmall = 1, turkeylarge = 1,             --  4  rare as farm stock
}

-- Herd sizes for cattle only. The Kentucky pattern was the small cow-calf
-- operation -- an average of about 25 cows per farm, with calves on the ground
-- most of the year. Vanilla's 1-3 cows with a 5% calf chance reads as a
-- hobbyist's back field, not a working farm.
--
-- Deliberately a little under the real average of 25: every animal here is
-- simulated continuously, so a hundred map farms at true size is a cost the
-- mod should not impose by default.
local CATTLE = {
    cow = {
        minFemaleNb = 8, maxFemaleNb = 16,
        minMaleNb = 1, maxMaleNb = 1,
        chanceForBaby = 35,
    },
    cowlarge = {
        minFemaleNb = 16, maxFemaleNb = 28,
        minMaleNb = 1, maxMaleNb = 2,
        chanceForBaby = 40,
    },
}

function KW.applyRanch()
    if not (RanchZoneDefinitions and RanchZoneDefinitions.type) then
        KW.log("ranch definitions not loaded yet; deferring")
        return false
    end

    if not KW.getOption("RebalanceFarms", true) then
        return true
    end

    local touched = 0
    for key, weight in pairs(WEIGHTS) do
        local def = RanchZoneDefinitions.type[key]
        if def then
            def.chance = weight
            touched = touched + 1
        end
    end

    for key, sizes in pairs(CATTLE) do
        local def = RanchZoneDefinitions.type[key]
        if def then
            for field, value in pairs(sizes) do
                def[field] = value
            end
            -- The spawner assumes these hold; a mod loading after us could
            -- leave them crossed over.
            if def.maxFemaleNb < def.minFemaleNb then
                def.maxFemaleNb = def.minFemaleNb
            end
            if def.maxMaleNb < def.minMaleNb then
                def.maxMaleNb = def.minMaleNb
            end
        end
    end

    KW.logChange("ranch", string.format(
        "farm weights rebalanced (%d types) -- cattle %d vs sheep %d",
        touched,
        (WEIGHTS.cow + WEIGHTS.cowlarge),
        (WEIGHTS.sheep + WEIGHTS.sheepsmall + WEIGHTS.sheeplarge)))
    return true
end

KW.applyRanch()

if Events then
    if Events.OnGameBoot then Events.OnGameBoot.Add(KW.applyRanch) end
    if Events.OnInitGlobalModData then Events.OnInitGlobalModData.Add(KW.applyRanch) end
    if Events.OnGameStart then Events.OnGameStart.Add(KW.applyRanch) end
end
