-- Knox Life -- shared setup, settings and logging.
--
-- Everything this mod does is a patch applied on top of the vanilla tables. We
-- deliberately never ship a file at a vanilla path: replacing, say,
-- MigrationGroupDefinitions.lua wholesale is what makes the existing wildlife
-- mods collide with each other and with future game patches.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

KW.VERSION = "0.2.0"

-- Addon contract version. Bumped only for a BREAKING change to the functions
-- below; additive changes leave it alone. An addon can refuse to load politely:
--
--     if not KnoxLife or (KnoxLife.API_VERSION or 0) < 1 then return end
--
KW.API_VERSION = 1

-- Registries an addon writes into. Populated by registerSpecies/addToBucket
-- rather than edited directly, so validation runs and mistakes get reported
-- instead of surfacing later as a crash in the animal pathfinder.
KW.species = KW.species or {}
KW.buckets = KW.buckets or {}

-- ROUTES COME FROM DENSITY, NOT FROM SHARES OF A FIXED POT.
--
-- This used to be a route budget divided between species by weight, and the flaw
-- was structural: every change robbed everything else. Shrinking the rabbit group
-- cost deer 33 routes for no reason anyone would recognise, and adding a species
-- thinned all the others. Worse, the sqrt compression used to keep rare animals
-- findable inverted the realism it was meant to serve. Measured against true 1993
-- Kentucky density, it produced squirrels at 6% and bobcats at 330%.
--
-- So each species now owns an absolute target and nobody else's number moves:
--
--     routes = density_per_sq_mi * HABITAT_SQ_MI / mean_group_size * fraction
--
-- One route is one family group, hence the division: a turkey flock of twelve
-- and a solitary bobcat are not comparable per animal. `fraction` is a single
-- dial across every species, so "this world runs at half of 1993" is a claim you
-- can actually make. Adding a species ADDS routes, which the measurements say we
-- can afford: boot, CPU and memory are flat from 2,814 zones to 13,230.
KW.HABITAT_SQ_MI = 141 * 0.63

-- Wildlife Density is now a realism fraction, and 1.0 means the real thing.
KW.DENSITY_SCALE = { 0.25, 0.5, 1.0, 1.5, 2.0 }

-- No species drops below this while it is enabled. At low fractions a bobcat
-- works out at four routes for the whole map and is effectively not in the game.
-- This is the one deliberate distortion, kept in a single visible place rather
-- than bent into every species' number the way the old sqrt did.
KW.MIN_ROUTES = 20

-- Multiplier on the DEER density only. Deer are 11.4 per square mile in reality
-- and the hunting loop is built around them, so this is the honest way to say
-- "more deer than Kentucky had" without pretending it is realism.
KW.SPECIES_MIX = {
    { id = "realistic", deer = 1.0 },
    { id = "balanced",  deer = 2.0 },
    { id = "deer",      deer = 3.3 },
}

-- Multiplier applied to group sizes, indexed by the Group Size setting.
-- Normal (3) is 1.0, because vanilla's family sizes are already right, with the
-- one documented exception of rabbits (see KW_Groups).
KW.GROUP_SCALE = { 0.5, 0.75, 1.0, 1.5, 2.25 }

function KW.log(msg)
    print("[KnoxLife] " .. tostring(msg))
end

-- Both patches are hooked to three separate events, because the sandbox values
-- they depend on are not available at the same point on a client, a host and a
-- dedicated server. That is correct but noisy: the same summary would print
-- three times per boot. Log only when the result actually changes.
local lastLogged = {}
function KW.logChange(key, msg)
    if lastLogged[key] == msg then return end
    lastLogged[key] = msg
    KW.log(msg)
end

-- SandboxVars is not populated when shared files first run, so every read goes
-- through here and falls back to the default until the world is up.
local function sandbox()
    return SandboxVars and SandboxVars.KnoxLife or nil
end

function KW.getOption(name, fallback)
    local vars = sandbox()
    if vars == nil then return fallback end
    local v = vars[name]
    if v == nil then return fallback end
    return v
end

function KW.settingsReady()
    return sandbox() ~= nil
end

-- Enum options come back as 1-based integers. Clamp before indexing so a bad
-- config value degrades to the default instead of erroring.
-- PREVIEW OVERRIDE.
--
-- KW.preview, when set, is a table of { OptionName = index } that stands in for
-- the sandbox for the duration of one calculation. It exists so the in-game
-- planner can ask "what would THESE settings give?" without a second copy of the
-- population maths -- every formula below already routes through this function,
-- so overriding here moves the whole model at once.
--
-- Never left set: KW.withPreview is the only supported way in, and it clears on
-- the way out even if the body errors. A stuck preview would silently detune a
-- live world, which is exactly the class of bug this repo keeps finding.
KW.preview = nil

--- Run fn() as though the sandbox held `settings`. Passes through ALL results.
--
-- All of them, not just the first: KW.scaledGroupOf returns three values, and a
-- single-result wrapper would silently hand back min with max and maxMale as
-- nil. Nested calls restore the outer preview rather than clearing to live.
function KW.withPreview(settings, fn)
    local saved = KW.preview
    KW.preview = settings
    local res = table.pack(pcall(fn))
    KW.preview = saved
    if not res[1] then
        KW.log("preview failed: " .. tostring(res[2]))
        return nil
    end
    return table.unpack(res, 2, res.n)
end

function KW.pickFromScale(scale, name, defaultIndex)
    local i = KW.preview and KW.preview[name] or KW.getOption(name, defaultIndex)
    i = math.floor(tonumber(i) or defaultIndex)
    if i < 1 then i = 1 end
    if i > #scale then i = #scale end
    return scale[i]
end

--- May this player reach the admin/debug tools?
--
-- Lifted out of KW_Locator so KW_AdminMenu cannot disagree with it. They did:
-- the locator showed while the admin menu did not, on the same server, for the
-- same player -- because the locator had already been fixed and the admin menu
-- still called isAdmin().
--
-- isAdmin() is a Java-exposed global with no Lua definition to read, and this
-- repo has been burned by it once already: a file-local isAdmin(player) shadowed
-- the zero-arg global, so it returned false for every real admin and the menu
-- was quietly debug-only on MP. getAccessLevel() is a string and says what it
-- means, so read that instead and never mind isAdmin().
function KW.mayUseAdminTools()
    if isDebugEnabled and isDebugEnabled() then return true end
    if isClient and isClient() then
        local lvl = string.lower(tostring(getAccessLevel and getAccessLevel() or ""))
        return lvl == "admin" or lvl == "moderator"
    end
    -- Singleplayer or the coop host. Permissive fallback: an existing save has no
    -- stored value for an option that did not exist when it was created.
    if not KW.getOption then return true end
    return KW.getOption("AdminTools", true) and true or false
end

--- How real this world is, as a fraction. 1.0 is true 1993 Kentucky density.
function KW.realismFraction()
    return KW.pickFromScale(KW.DENSITY_SCALE, "RouteDensity", 3)
end

--- The chosen species mix, as a table from KW.SPECIES_MIX.
function KW.speciesMix()
    return KW.pickFromScale(KW.SPECIES_MIX, "SpeciesMix", 1)
end

--- Mean animals in one family group, as the group is actually configured.
--
-- Read from MigrationGroupDefinitions rather than our own registry, because that
-- is the table the sandbox Group Size setting has already scaled. minAnimal and
-- maxAnimal count FEMALES; males and babies are added on top, which is the trap
-- documented in KW_Groups.lua and the reason a "max 5" deer group is eleven.
--- Family size for `def` under the CURRENT dials (or the previewed ones).
--
-- Extracted from KW_Groups so the planner and the live spawner cannot disagree.
-- Returns min, max, maxMale, with the two invariants the spawner assumes:
-- max >= min, and never more males than females.
function KW.scaledGroupOf(id, def)
    local own = KW.groupScaleFor(id)
    local mn = KW.scaleCount((tonumber(def.minAnimal) or 1) * own, 1)
    local mx = KW.scaleCount((tonumber(def.maxAnimal) or mn) * own, mn)
    if mx < mn then mx = mn end
    local ml = KW.scaleCount((tonumber(def.maxMale) or 1) * own, 1)
    if ml > mx then ml = mx end
    return mn, mx, ml
end

function KW.meanGroupSize(species)
    local g = MigrationGroupDefinitions and MigrationGroupDefinitions[species]
    -- Under preview, MigrationGroupDefinitions is the wrong source: it was
    -- scaled by the dials the world is ACTUALLY running, not the ones being
    -- previewed. Recompute from the registered def instead, through the same
    -- scaling the spawner uses.
    if KW.preview then
        local def = KW.species and KW.species[species]
        if def then
            local mn, mx, ml = KW.scaledGroupOf(species, def)
            g = { minAnimal = mn, maxAnimal = mx, maxMale = ml,
                  babyChance = def.babyChance }
        end
    end
    if not g then return 0 end
    local lo = tonumber(g.minAnimal) or 1
    local hi = tonumber(g.maxAnimal) or lo
    local females = (lo + hi) / 2.0
    local males = (tonumber(g.maxMale) or 0) / 2.0
    local babies = females * ((tonumber(g.babyChance) or 0) / 100.0)
    return females + males + babies
end

-- A species that declares no density is guessed at, loudly. This is the "an
-- addon written before densities existed" case: better a plausible uncommon
-- mammal than nothing at all, and better still that the author sees the warning
-- and puts a real number in.
KW.DEFAULT_DENSITY = 2.0
local warnedDensity = {}

--- How many routes a species should have, before pool limits.
--
-- This is the whole model in six lines. Density is a real-world figure the
-- species owns; dividing by group size converts animals into family groups,
-- which is what a route actually is; the fraction is the single global dial; and
-- the floor keeps a genuinely rare animal from rounding out of the game.
function KW.targetRoutes(id)
    local def = KW.species[id]
    if not def then return 0 end

    local density = tonumber(def.density)
    if not density then
        density = KW.DEFAULT_DENSITY
        if not warnedDensity[id] then
            warnedDensity[id] = true
            KW.log(string.format(
                "'%s' declares no density, so it is guessed at %.1f per sq mi. "
                .. "Add `density = <animals per square mile>` to registerSpecies.",
                id, density))
        end
    end
    if id == "deer" then
        density = density * (KW.speciesMix().deer or 1.0)
    end

    local group = KW.meanGroupSize(id)
    if group <= 0 then return 0 end

    -- Global realism, then this species' own multiplier. They compose: an admin
    -- can run the world at half density and still double the deer.
    local want = (density * KW.HABITAT_SQ_MI / group)
        * KW.realismFraction() * KW.routeScaleFor(id)
    want = math.floor(want + 0.5)
    if want < KW.MIN_ROUTES then want = KW.MIN_ROUTES end
    return want
end

function KW.groupScale()
    return KW.pickFromScale(KW.GROUP_SCALE, "GroupSize", 3)
end

-- Scale a count, keeping it at least `floor`. Group sizes are small integers,
-- so rounding matters more than it looks: without the floor, a 0.5 multiplier
-- would turn a lone raccoon sow into zero animals.
function KW.scaleCount(base, floorValue)
    local scaled = math.floor((base * KW.groupScale()) + 0.5)
    local minimum = floorValue or 1
    if scaled < minimum then scaled = minimum end
    return scaled
end

-- ---------------------------------------------------------------------------
-- Public API for addons
--
-- The routes are the platform; species are the plugins. A route is typed
-- "large" or "small", and when it spawns the game rolls across everything
-- registered in that bucket by weight. So an addon that adds a species does
-- NOT ship route data, touch the generator, or care where the forests are --
-- it registers a species and a weight and inherits every route on the map.
--
-- Declare `require=KnoxLife` in the addon's mod.info. That guarantees this
-- file loads first, so the functions exist by the time the addon's own files
-- run, and the registrations land before anything is applied to the game.
-- ---------------------------------------------------------------------------

local REQUIRED_FIELDS = { "female", "male", "baby", "possibleBreed" }

-- Which baked route pool a species walks when it does not name one. The buckets
-- stay exactly as documented, so `addToBucket("small", "coyote", 18)` keeps
-- working; this only decides which habitat those routes were generated for.
-- Deer ground is the generic large-mammal case and rabbit ground is the generic
-- small-game case, which is what the old shared "small" profile approximated.
KW.POOL_FALLBACK = { large = "deer", small = "rabbit" }

--- Register (or replace) a species that can spawn on migration routes.
--
-- @param id     unique key, e.g. "coyote"
-- @param def    table:
--   female, male, baby   REQUIRED. Animal type names from AnimalDefinitions.
--   possibleBreed        REQUIRED. Comma-separated breed list. A nil here
--                        crashes animal chunk loading, so it is enforced.
--   minAnimal, maxAnimal FEMALES per group; males and babies are added on top.
--   maxMale, babyChance  babyChance is a percentage.
--   trackSize, speed     "small"/"medium"/"large"; speed 1.0 is base.
--   enabledOption        optional sandbox key gating this species on/off.
--   timing               optional table overriding the shared eat/sleep timers.
--   habitat              optional. Which baked route pool this species walks:
--                        "deer", "rabbit", "turkey" or "raccoon". Omit it and
--                        the species inherits its bucket's pool, which is what
--                        every addon written against API 1 already gets.
--                        Pick the animal that lives most like yours: a coyote
--                        wants "deer" for the range, a fox "raccoon" for the
--                        riparian and human edge.
function KW.registerSpecies(id, def)
    if type(id) ~= "string" or id == "" then
        KW.log("registerSpecies: id must be a non-empty string")
        return false
    end
    if type(def) ~= "table" then
        KW.log("registerSpecies('" .. id .. "'): def must be a table")
        return false
    end
    for _, field in ipairs(REQUIRED_FIELDS) do
        if def[field] == nil or def[field] == "" then
            KW.log("registerSpecies('" .. id .. "'): missing required field '"
                .. field .. "' -- refusing to register, as this would crash "
                .. "animal chunk loading later")
            return false
        end
    end

    local copy = {}
    for k, v in pairs(def) do copy[k] = v end
    copy.minAnimal = tonumber(copy.minAnimal) or 1
    copy.maxAnimal = tonumber(copy.maxAnimal) or copy.minAnimal
    copy.maxMale = tonumber(copy.maxMale) or 1
    copy.babyChance = tonumber(copy.babyChance) or 0
    copy.trackSize = copy.trackSize or "medium"
    copy.speed = tonumber(copy.speed) or 0.05

    -- Only a type check here. Whether the pool EXISTS cannot be asked yet:
    -- shared files load alphabetically, so KW_Groups.lua registers the core
    -- species before KW_RouteData.lua has defined KW.Routes. Checking against an
    -- empty table at this point rejected every habitat including our own four,
    -- silently sending all of them to the bucket fallback.
    if copy.habitat ~= nil and type(copy.habitat) ~= "string" then
        KW.log("registerSpecies('" .. id .. "'): habitat must be a string, got "
            .. type(copy.habitat) .. " -- ignoring it")
        copy.habitat = nil
    end

    KW.species[id] = copy
    return true
end

--- Which route pool a species walks, resolving the bucket fallback.
--
-- The existence check lives here rather than in registerSpecies because this
-- runs at world load, by which point KW.Routes is populated.
function KW.habitatFor(id)
    local def = KW.species[id]
    local pools = KW.Routes or {}

    local bucketPool
    for bucket, members in pairs(KW.buckets) do
        if members[id] ~= nil then
            bucketPool = KW.POOL_FALLBACK[bucket] or bucket
            break
        end
    end

    if def and def.habitat then
        if pools[def.habitat] ~= nil then return def.habitat end
        KW.log(string.format(
            "'%s' asks for habitat '%s', which has no baked routes; using '%s'",
            id, def.habitat, tostring(bucketPool)))
    end
    return bucketPool
end

--- True unless a sandbox option switches this species off.
--
-- `enabledOption` is read from this mod's own sandbox page by default, which is
-- right for the four species we ship and useless to an addon: its options live
-- under its own mod id. So a dotted name is read from there instead:
--
--     enabledOption = "Fox"                        SandboxVars.KnoxLife.Fox
--     enabledOption = "KnoxLifeFoxes.Fox"   its own page
--
-- Plain names keep working, so nothing written against API 1 changes.
--- Read a sandbox option that may live on another mod's page.
--
--     "WildTurkey"                  -> SandboxVars.KnoxLife.WildTurkey
--     "KnoxLifeFoxes.FoxRoutes"     -> SandboxVars.KnoxLifeFoxes.FoxRoutes
--
-- The dotted form is what lets a species mod keep its settings on its own page
-- instead of cluttering ours, which matters now that every creature is a mod.
function KW.readOption(opt, fallback)
    if not opt then return fallback end
    local dot = string.find(opt, ".", 1, true)
    if not dot then return KW.getOption(opt, fallback) end

    local page = string.sub(opt, 1, dot - 1)
    local key = string.sub(opt, dot + 1)
    local vars = SandboxVars and SandboxVars[page]
    if vars == nil then return fallback end    -- settings not up yet
    local v = vars[key]
    if v == nil then return fallback end
    return v
end

function KW.speciesEnabled(def)
    if not def then return false end
    if not def.enabledOption then return true end
    return KW.readOption(def.enabledOption, true) and true or false
end

-- Per-species multipliers, so an admin can tune one animal without touching any
-- other. Both default to index 3, which is 1.0 and changes nothing.
KW.SPECIES_SCALE = { 0.25, 0.5, 1.0, 1.5, 2.0 }

local function speciesScale(def, key)
    if not def or not def[key] then return 1.0 end
    local i = math.floor(tonumber(KW.readOption(def[key], 3)) or 3)
    if i < 1 then i = 1 end
    if i > #KW.SPECIES_SCALE then i = #KW.SPECIES_SCALE end
    return KW.SPECIES_SCALE[i]
end

--- Multiplier on how many routes this species gets. Admin-facing.
function KW.routeScaleFor(id)
    return speciesScale(KW.species[id], "routeOption")
end

--- Multiplier on this species' group size, on top of the global Group Size.
function KW.groupScaleFor(id)
    return speciesScale(KW.species[id], "groupOption")
end

--- Divide `total` between `weights` so the parts sum to exactly `total`.
--
-- Largest remainder, not plain rounding. Rounding each share independently
-- loses or gains routes against the density the player asked for, and with a
-- long tail like turkey it is the small share that gets rounded to nothing.
function KW.apportion(weights, total)
    -- Every id that was asked about gets an answer, including 0. Returning nil
    -- for a zero weight would look harmless and then blow up at the caller,
    -- because `nil > 0` is an error in Lua rather than false.
    local sum, ids, out = 0, {}, {}
    for id, w in pairs(weights) do
        ids[#ids + 1] = id
        out[id] = 0
        if w > 0 then sum = sum + w end
    end
    table.sort(ids)   -- deterministic: pairs() order is not stable in Lua
    if sum <= 0 or total <= 0 then
        return out
    end

    local given, rema = 0, {}
    for _, id in ipairs(ids) do
        local w = weights[id]
        if w > 0 then
            local exact = total * w / sum
            local whole = math.floor(exact)
            out[id] = whole
            given = given + whole
            rema[#rema + 1] = { id = id, frac = exact - whole }
        end
    end
    table.sort(rema, function(a, b)
        if a.frac == b.frac then return a.id < b.id end
        return a.frac > b.frac
    end)
    local i = 1
    while given < total and #rema > 0 do
        local pick = rema[((i - 1) % #rema) + 1]
        out[pick.id] = out[pick.id] + 1
        given = given + 1
        i = i + 1
    end
    return out
end

--- Work out which routes each species gets, before any of them are registered.
--
-- Returns a list of { species, pool, first, count }, where `first` is a 1-based
-- index into KnoxLife.Routes[pool]. Slices of the same pool never overlap,
-- so two species sharing a habitat cannot both be handed the same geometry and
-- register two zones on top of each other.
--
-- Every species gets its own target. Nothing is shared, so nothing is stolen.
--
-- The old version divided one budget by weight, which meant any change to any
-- species silently moved every other one. That is gone: a species asks for what
-- its density says, takes it if the map has it, and reports the shortfall if not.
--
-- Two species CAN still share a pool, when an addon points its habitat at one of
-- ours. They get disjoint slices, first come by sorted name, and whoever misses
-- out is logged rather than quietly short-changed.
function KW.allocateRoutes()
    local pools = KW.Routes or {}
    local cursor, plan, total = {}, {}, 0

    local ids = {}
    for _, members in pairs(KW.buckets) do
        for id in pairs(members) do
            local def = KW.species[id]
            if def and KW.speciesEnabled(def) then ids[#ids + 1] = id end
        end
    end
    table.sort(ids)     -- deterministic: pairs() order is not stable in Lua

    for _, id in ipairs(ids) do
        local want = KW.targetRoutes(id)
        local pool = KW.habitatFor(id)
        local available = pool and pools[pool] and #pools[pool] or 0
        if want > 0 and available > 0 then
            local at = (cursor[pool] or 0) + 1
            local take = math.min(want, available - at + 1)
            if take > 0 then
                cursor[pool] = at + take - 1
                total = total + take
                plan[#plan + 1] = {
                    species = id, pool = pool, first = at,
                    count = take, wanted = want,
                }
            end
        elseif want > 0 then
            KW.log(string.format(
                "%s wants %d routes but pool '%s' is empty; skipping",
                id, want, tostring(pool)))
        end
    end
    return plan, total
end

--- Put a species into a route bucket, with a weight relative to the others.
--
-- @param bucket  "large" (deer-scale routes) or "small"
-- @param id      a species previously passed to registerSpecies
-- @param weight  LARGELY VESTIGIAL since routes came to be set by density. It
--                is kept because it is public API from version 1 and an addon
--                supplies one. It still decides nothing except in the legacy
--                path for a species that declares no `density`.
function KW.addToBucket(bucket, id, weight)
    if bucket ~= "large" and bucket ~= "small" then
        KW.log("addToBucket: bucket must be 'large' or 'small', got "
            .. tostring(bucket))
        return false
    end
    KW.buckets[bucket] = KW.buckets[bucket] or {}
    KW.buckets[bucket][id] = tonumber(weight) or 50
    return true
end

--- Give the mod a route pool of your own, so your species walks its own ground.
--
-- @param name   pool name, matching the `habitat` you give registerSpecies.
--               Prefix it: `kwc_fox`, not `fox`.
-- @param pool   list of { follow = {x,y,...}, eat = {...}, sleep = {...} },
--               ordered best habitat first. Bake it with the base mod's
--               generator, which takes a habitat definition as JSON:
--
--                 python3 tools/gen_routes.py --profile-help
--
-- Without this, an addon species walks whichever base pool its bucket falls
-- back to, which is fine for something raccoon-shaped and wrong for a bobcat.
-- With it, the addon inherits nothing: its own habitat, its own geometry.
function KW.registerRoutePool(name, pool)
    if type(name) ~= "string" or name == "" then
        KW.log("registerRoutePool: name must be a non-empty string")
        return false
    end
    if type(pool) ~= "table" or #pool == 0 then
        KW.log("registerRoutePool('" .. name .. "'): pool must be a non-empty list")
        return false
    end
    KW.Routes = KW.Routes or {}
    if KW.Routes[name] ~= nil then
        KW.log("registerRoutePool('" .. name .. "'): a pool by that name already "
            .. "exists and will not be replaced. Prefix yours with your mod id.")
        return false
    end
    -- Validate the one invariant the engine dies without: every eat and sleep
    -- leg must share an EXACT vertex with its route's follow leg, because
    -- addJunctionsWithOtherZone matches points, not proximity. A leg that never
    -- touches its follow line keeps a null junction list, and the pathfinder
    -- dereferences it every tick -- roughly a thousand NullPointerExceptions a
    -- minute, hours after this call returned "fine". Reject the pool loudly now
    -- instead. (The private generator enforces this at bake time; hand-authored
    -- pools had no guard at all until here.)
    for ri, route in ipairs(pool) do
        local f = route.follow
        if type(f) ~= "table" or #f < 4 or #f % 2 ~= 0 then
            KW.log(string.format("registerRoutePool('%s'): route %d has no usable "
                .. "follow leg (need an even, >=4 flat list of x,y). Rejected.",
                name, ri))
            return false
        end
        local onFollow = {}
        for i = 1, #f - 1, 2 do
            onFollow[f[i] .. "," .. f[i + 1]] = true
        end
        for _, legName in ipairs({ "eat", "sleep" }) do
            local leg = route[legName]
            if leg ~= nil then
                local touches = false
                for i = 1, #leg - 1, 2 do
                    if onFollow[leg[i] .. "," .. leg[i + 1]] then
                        touches = true
                        break
                    end
                end
                if not touches then
                    KW.log(string.format("registerRoutePool('%s'): route %d's %s "
                        .. "leg shares no exact vertex with its follow leg. The "
                        .. "engine joins zones by identical points; this route "
                        .. "would NPE-storm at runtime. Rejected -- move one %s "
                        .. "vertex onto the follow line.",
                        name, ri, legName, legName))
                    return false
                end
            end
        end
    end
    KW.Routes[name] = pool
    -- Routes that arrive from an addon are extra, not a share of the base mod's
    -- budget. See KW.allocateRoutes for why.
    KW.addonPools = KW.addonPools or {}
    KW.addonPools[name] = true
    return true
end

--- Remove a species from a bucket. It stays registered, just stops spawning.
function KW.removeFromBucket(bucket, id)
    if KW.buckets[bucket] then KW.buckets[bucket][id] = nil end
end

--- True if a species is registered. Useful for addon-to-addon compatibility.
function KW.hasSpecies(id)
    return KW.species[id] ~= nil
end

-- Warn about the mods this one supersedes. Both mutate the same tables, and
-- whichever applies last wins, so running them together produces whatever the
-- load order happens to decide rather than what either mod intends.
function KW.warnAboutConflicts()
    if KW._warned then return end
    KW._warned = true

    if AnimalsEverywhere ~= nil then
        KW.log("WARNING: 'Animals Everywhere' is active. It multiplies group "
            .. "sizes by up to 10x on top of this mod, which is exactly the "
            .. "blob behaviour this mod exists to fix. Disable it.")
    end

    -- Wild Turkeys ships a full replacement of the vanilla migration file, so
    -- it cannot be detected by a global. Its turkey group is harmless if ours
    -- is enabled -- we overwrite it -- but say so, because its copy of the
    -- vanilla file also reverts any other mod's changes to that file.
    if MigrationGroupDefinitions and MigrationGroupDefinitions["turkey"]
        and not KW._appliedTurkey then
        KW.log("NOTE: a turkey migration group already exists (probably the "
            .. "'Wild Turkeys' mod). Ours will replace it.")
    end
end
