--- Stage 2 of the threat/courage design: predators hunt prey. No Java agent.
---
--- WHY THIS DOES NOT NEED AN ATTACK ANIMATION
---
--- It would like one. It cannot have one: `animset` keys both media/AnimSets/
--- and actiongroups/, and only the first is reachable from a mod, so no mod can
--- give an animal a new action state. STATUS 7h has the disassembly.
---
--- But an attack is contact, consequence and feedback, and all three are
--- reachable from Lua. What is lost is the strike itself -- a predator closes by
--- walking and the bite lands without a lunge. That is the ONLY thing a Java
--- agent buys here, which is exactly why it belongs in an optional addon rather
--- than in the requirements.
---
--- ⚠️ PREY ONLY. Players and zombies are stage 3 and are deliberately not
--- reachable from this file. That is not caution for its own sake: it removes
--- the balance question, the aggression-at-players question, and the infection
--- question in one go. When it does reach players, prove that a coyote bite
--- cannot transmit the knox virus before shipping it, do not infer it.
---
--- COST
---
--- The arithmetic is free; "who is near me" is not. So the expensive scan runs
--- once a game minute and only for predators, while engaged hunts advance on a
--- cheap per-pair check. A hunt is a handful of pairs, not a world sweep.

if isClient and isClient() then return end

KnoxLife = KnoxLife or {}
local KW = KnoxLife

KW.Predation = KW.Predation or {}
local P = KW.Predation

-- Radius, in tiles, a predator looks for prey in. Deliberately short: a wolf
-- that notices you across a field is a horror game, not an ecology.
P.SENSE = 12
-- Tiles at which a bite lands. Matches the attackDist stage 1 gave the canids.
P.REACH = 1.6
-- Game minutes a predator waits between bites. attackTimer is engine-side and
-- unused here, because nothing plays the animation that would carry it.
P.BITE_COOLDOWN = 1
-- Fraction of a prey animal's health a bite removes at parity. Attrition rather
-- than an instant kill: it buys chases, escapes and wounded animals, which is
-- most of what makes a food chain read as one.
P.BITE = 0.34

--- threat: what you are worth in a fight, summed on both sides.
--- courage: the advantage you need before you will START one. No courage means
--- this species never initiates -- which is what makes prey prey.
KW.THREAT = KW.THREAT or {
    kwc_squirrel = 1.0, rabbit = 1.5, turkey = 2.0, raccoon = 3.0,
    kwc_fox = 3.5, kwc_coyote = 5.0, kwc_bobcat = 5.0, deer = 6.0,
}
KW.COURAGE = KW.COURAGE or {
    kwc_coyote = 1.2,    -- pack opportunist
    kwc_bobcat = 2.5,    -- solitary ambusher; never packs
    kwc_fox    = 3.0,    -- very cautious, small prey only
}

--- Declare an addon species' place in the food chain.
---
--- One required number and one optional one, matching how `density` already
--- works: nothing here is shared, so nothing is stolen, and a bear that declares
--- a threat is immediately something every existing predator can reason about.
--- Omit `courage` and your species never initiates.
function KW.setThreat(id, threat, courage)
    if type(id) ~= "string" or not tonumber(threat) then return false end
    KW.THREAT[id] = tonumber(threat)
    if courage ~= nil then KW.COURAGE[id] = tonumber(courage) end
    return true
end

-- ⚠️ getAnimalType() returns a LIFE-STAGE id, not a group id.
--
-- A live fox reports `kwc_foxvixen`, `kwc_foxdog` or `kwc_foxkit`; a rabbit
-- reports `rabdoe` or `rabbuck`. THREAT and COURAGE are keyed by the MIGRATION
-- GROUP -- `kwc_fox`, `rabbit` -- because that is the level a species is
-- declared at, and asking one about the other silently returns nil.
--
-- Which meant every threat lookup returned 0, every predator failed the
-- `threat > 0` test, and predation never fired once. Our own nearby report had
-- been printing `kwc_foxvixen` for hours.
local groupCache = {}

local function groupOf(stageId)
    local hit = groupCache[stageId]
    if hit ~= nil then return hit end
    local found = stageId                    -- already a group id, or unknown
    for gid, g in pairs(MigrationGroupDefinitions or {}) do
        if g and (g.female == stageId or g.male == stageId or g.baby == stageId) then
            found = gid
            break
        end
    end
    groupCache[stageId] = found
    return found
end

--- Exposed so the tests can prove a stage id resolves, without a live world.
KW.groupOf = groupOf

local function threatOf(a)
    local ok, t = pcall(function() return a:getAnimalType() end)
    if not ok or not t then return 0 end
    local base = KW.THREAT[groupOf(tostring(t))]
    if not base then return 0 end
    -- A baby counts for a third, and a wounded animal for what is left of it.
    -- Predators go for the weak, which is both true and better drama.
    local mult = 1.0
    pcall(function() if a:isBaby() then mult = 0.34 end end)
    local hp = 1.0
    pcall(function() hp = math.max(0.2, a:getHealth() or 1.0) end)
    return base * mult * hp
end

-- ---------------------------------------------------------------------------
-- THE SEAM. A Java addon replaces this and calls through for the damage.
--
-- Everything above decides WHETHER a bite happens. This decides what a bite
-- looks like, and it is the single thing worth overriding: with ZombieBuddy
-- present, an addon can patch ActionGroup.load (STATUS 7h), gain a real attack
-- state, and register a handler that plays the lunge before calling `previous`.
--
--     local prev                       -- ⚠️ DECLARE FIRST, on its own line
--     prev = KW.setStrikeHandler(function(pred, prey)
--         playTheLunge(pred)
--         return prev(pred, prey)          -- keep the damage, add the animation
--     end)
--
-- ⚠️ `local prev = KW.setStrikeHandler(function() ... prev ... end)` looks
-- identical and is broken: in Lua a local is only in scope AFTER its statement,
-- so the closure captures a different (nil) `prev`, the call through never
-- happens, and the addon silently does no damage while appearing to work. This
-- comment had it wrong until a test caught it.
--
-- Returning the previous handler is what makes that chain possible, and is why
-- this is a setter rather than a field an addon overwrites.
-- ---------------------------------------------------------------------------

local function defaultStrike(predator, prey)
    local hp = 1.0
    pcall(function() hp = prey:getHealth() or 1.0 end)

    -- Scale the bite by how outmatched the prey is, so a coyote ends a squirrel
    -- quickly and a rabbit gets a chance to break away from a fox.
    local pw, qw = threatOf(predator), threatOf(prey)
    local ratio = (qw > 0) and (pw / qw) or 4.0
    local bite = P.BITE * math.max(0.5, math.min(2.0, ratio / 2.0))

    local left = hp - bite
    pcall(function() prey:addBlood(nil, false, true, true) end)
    if left <= 0 then
        -- Vanilla's own way of killing an animal from Lua
        -- (ClientCommands.lua:851). setAttackedBy first, so anything watching
        -- OnAnimalDead -- KnoxLifeOverkill included -- sees a killer.
        pcall(function() prey:setAttackedBy(predator) end)
        pcall(function() prey:setHealth(0) end)
        return true, 0
    end
    pcall(function() prey:setHealth(left) end)
    return false, left
end

P.strike = defaultStrike

--- Replace how a bite is delivered. Returns the handler you replaced.
function KW.setStrikeHandler(fn)
    if type(fn) ~= "function" then return P.strike end
    local prev = P.strike
    P.strike = fn
    return prev
end

-- ---------------------------------------------------------------------------
-- Finding a fight.
--
-- ⚠️ BIN, DO NOT PAIR. A world can hold several thousand loaded animals, and
-- comparing every predator against every animal is tens of millions of distance
-- checks a minute. Binning on a SENSE-sized grid and looking only at the nine
-- neighbouring bins turns that into a handful of comparisons per predator,
-- because a predator that cannot sense you cannot be told about you.
-- ---------------------------------------------------------------------------

local hunts = {}          -- predator id -> { prey = animal, next = gameMinute }

local function idOf(a)
    local ok, v = pcall(function() return a:getOnlineID() end)
    return (ok and v) and tostring(v) or tostring(a)
end

local function alive(a)
    if not a then return false end
    local ok, dead = pcall(function() return a:isDead() end)
    if not ok then return false end
    if dead then return false end
    local okw, inworld = pcall(function() return a:isExistInTheWorld() end)
    return (not okw) or inworld
end

local function loadedAnimals()
    local cell = getCell and getCell()
    if not cell then return {} end
    local ok, list = pcall(function() return cell:getAnimals() end)
    if not ok or not list then return {} end
    local n = 0
    pcall(function() n = list:size() end)
    local out = {}
    for i = 0, n - 1 do
        local a = list:get(i)
        if alive(a) then out[#out + 1] = a end
    end
    return out
end

local function posOf(a)
    local ok, x, y = pcall(function() return a:getX(), a:getY() end)
    if not ok then return nil end
    return x, y
end

--- The rule from STATUS 7g, and the whole of it:
---     attack if  sum(my side)  >=  sum(their side) * my courage
local function willEngage(predator, prey, allies, rivals)
    local ok, t = pcall(function() return predator:getAnimalType() end)
    local courage = ok and t and KW.COURAGE[groupOf(tostring(t))]
    if not courage then return false end          -- prey never initiate
    return allies >= rivals * courage
end

--- One pass: pair predators with prey they will actually take on.
function KW.huntTick()
    if not KW.getOption("Predation", true) then return end

    local all = loadedAnimals()
    if #all < 2 then return end

    local B = P.SENSE
    local bins = {}
    local info = {}
    for _, a in ipairs(all) do
        local x, y = posOf(a)
        if x then
            local key = math.floor(x / B) .. ":" .. math.floor(y / B)
            bins[key] = bins[key] or {}
            table.insert(bins[key], a)
            info[a] = { x = x, y = y, threat = threatOf(a) }
        end
    end

    for _, pred in ipairs(all) do
        local me = info[pred]
        if me and me.threat > 0 and not hunts[idOf(pred)] then
            local bx, by = math.floor(me.x / B), math.floor(me.y / B)
            local allies, best, bestD = me.threat, nil, nil
            local rivals = 0
            for dx = -1, 1 do
                for dy = -1, 1 do
                    for _, other in ipairs(bins[(bx + dx) .. ":" .. (by + dy)] or {}) do
                        local it = info[other]
                        if it and other ~= pred then
                            local d = math.sqrt((it.x - me.x) ^ 2 + (it.y - me.y) ^ 2)
                            if d <= P.SENSE and it.threat > 0 then
                                local okp, tp = pcall(function() return other:getAnimalType() end)
                                local sameSide = okp and tp
                                    and KW.COURAGE[groupOf(tostring(tp))] ~= nil
                                if sameSide then
                                    -- another predator: counts toward the pack
                                    allies = allies + it.threat
                                elseif not bestD or d < bestD then
                                    best, bestD = other, d
                                    rivals = it.threat
                                end
                            end
                        end
                    end
                end
            end
            if best and willEngage(pred, best, allies, rivals) then
                hunts[idOf(pred)] = { pred = pred, prey = best, nxt = 0 }
                pcall(function() pred:getBehavior():goAttack(best) end)
            end
        end
    end
end

--- Advance the hunts that are already running. Cheap: a few pairs, not a sweep.
function KW.huntAdvance()
    if not KW.getOption("Predation", true) then hunts = {}; return end
    local now = 0
    pcall(function() now = getGameTime():getWorldAgeHours() * 60 end)

    for id, h in pairs(hunts) do
        if not (alive(h.pred) and alive(h.prey)) then
            hunts[id] = nil
        else
            local px, py = posOf(h.pred)
            local qx, qy = posOf(h.prey)
            if not (px and qx) then
                hunts[id] = nil
            else
                local d = math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
                if d > P.SENSE * 1.5 then
                    hunts[id] = nil                     -- it got away
                elseif d <= P.REACH and now >= (h.nxt or 0) then
                    h.nxt = now + P.BITE_COOLDOWN
                    local okS, died = pcall(P.strike, h.pred, h.prey)
                    if okS and died then
                        hunts[id] = nil
                    elseif not okS then
                        KW.log("strike handler failed: " .. tostring(died))
                        hunts[id] = nil
                    end
                end
            end
        end
    end
end

--- How many hunts are running. Public for the admin tools and the tests.
function KW.huntCount()
    local n = 0
    for _ in pairs(hunts) do n = n + 1 end
    return n
end

if Events then
    -- The expensive pass runs on the slow event; engaged pairs advance on the
    -- fast one. Both wrapped, because an error in a per-minute hook is an error
    -- every minute forever.
    if Events.EveryOneMinute then
        Events.EveryOneMinute.Add(function() pcall(KW.huntTick) end)
    end
    if Events.OnTick then
        Events.OnTick.Add(function() pcall(KW.huntAdvance) end)
    end
end

return P
