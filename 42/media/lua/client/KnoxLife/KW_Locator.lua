-- Knox Life -- admin locator.
--
-- Wild animals are hard to find on purpose: a migration route is a few hundred
-- tiles long, herds move along it, and they exist as meta simulation until you
-- are close enough to materialise them. That is correct for play and miserable
-- for testing, where you need to answer "is anything actually out there" in
-- under a minute.
--
-- This points the game's own world-marker arrow at the nearest route. It is the
-- same mechanism the treasure-hunt mods use: addPlayerHomingPoint draws a
-- homing arrow from the player toward a world coordinate, and addGridSquareMarker
-- puts a ring on the ground once you arrive.
--
-- Admin only. This is a testing aid, not a gameplay feature -- an arrow to the
-- nearest deer would gut the hunting the rest of the mod exists to create.

require "ISUI/ISWorldObjectContextMenu"

KnoxLife = KnoxLife or {}
local KW = KnoxLife

KW.Locator = KW.Locator or {}
local L = KW.Locator

L.arrow = nil
L.circle = nil
L.target = nil          -- {x, y, label}
L.ARRIVE_DIST = 25      -- tiles; close enough to call it found

-- NOTE: a file-local isAdmin(player) used to live here. It shadowed the
-- zero-arg Java global of the same name and returned false for every real
-- admin -- the original of the trap written up as STATUS item 7d. It had been
-- dead code since mayUseTools() started calling KW.mayUseAdminTools(), but a
-- dead shadow is still a loaded one, so it is gone rather than merely unused.

function L.clear()
    if L.circle then L.circle:remove(); L.circle = nil end
    if L.arrow then L.arrow:remove(); L.arrow = nil end
    L.target = nil
end

-- Routes are stored as flat {x1,y1,x2,y2,...}. We aim at the middle vertex
-- rather than the first: the herd walks the whole polyline, so the midpoint is
-- the closest thing to "where it probably is".
function L.midpointOf(follow)
    local pairsCount = math.floor(#follow / 2)
    if pairsCount < 1 then return nil end
    -- ceil, not floor. With floor a 3-vertex route picks vertex 1 -- the START
    -- -- which is what this function's own comment says it does not do. 136 of
    -- the 2,330 shipped routes are 3-vertex, so 5.8% of map dots sat at the
    -- start of the walk instead of the middle of it. ceil gives the true middle
    -- for an odd vertex count and is identical for an even one.
    local i = math.ceil(pairsCount / 2)
    if i < 1 then i = 1 end
    return follow[(i - 1) * 2 + 1], follow[(i - 1) * 2 + 2]
end
local midpointOf = L.midpointOf

-- Only the first N routes of a class are actually registered, per the density
-- setting, so pointing at route 200 when 130 are live would send you to an
-- empty forest.
-- Ask the allocator what was ACTUALLY registered, rather than guessing.
--
-- This used to look up KW.Routes["large"] and search the first routeBudget() of
-- them, which was right when there were two pools named after size classes and
-- each got the whole budget. Both halves are now wrong: the pools are named
-- after species, so the lookup found nothing and every search reported "no
-- routes registered"; and a species gets a SLICE of the budget, so searching
-- the first N would have pointed at routes nobody registered.
--
-- Reading the plan fixes both and costs nothing to maintain: addon species
-- appear in this menu the moment they register, with no code here mentioning
-- them.
function L.plan()
    if not KW.allocateRoutes then return {} end
    local ok, plan = pcall(KW.allocateRoutes)
    if not ok or type(plan) ~= "table" then return {} end
    local out = {}
    for _, p in ipairs(plan) do
        if p.count > 0 and KW.Routes and KW.Routes[p.pool] then
            out[#out + 1] = p
        end
    end
    return out
end

-- "kwc_bobcat" is not a label. Drop a mod prefix and capitalise.
function L.labelFor(id)
    local name = string.match(id, "^[%a]+_(.+)$") or id
    return (string.gsub(name, "^%l", string.upper))
end

function L.findNearest(part, px, py)
    local pool = KW.Routes and KW.Routes[part.pool]
    if not pool then return nil end

    local bestX, bestY, bestD, bestI
    local last = math.min(part.first + part.count - 1, #pool)
    for i = part.first, last do
        local r = pool[i]
        -- NOT `local mx, my = r and midpointOf(...)`. `and` is an expression and
        -- yields ONE value, so the second return is silently discarded and my is
        -- always nil. Guard with a statement instead.
        local mx, my
        if r then mx, my = midpointOf(r.follow) end
        if mx and my then
            local dx, dy = mx - px, my - py
            local d = (dx * dx) + (dy * dy)
            if not bestD or d < bestD then
                bestD, bestX, bestY, bestI = d, mx, my, i
            end
        end
    end
    if not bestD then return nil end
    return bestX, bestY, math.sqrt(bestD), bestI
end

-- A stable colour per species, so two markers are never confusable and the same
-- animal is always the same colour between sessions.
--
-- The hash below was ALL of this function, and its own comment claimed it made
-- two markers never confusable. It did the opposite. Hashing a name to a single
-- hue puts every species on one 360-value wheel, and with eight of them the
-- wheel collided badly: rabbit #C226BC, fox #BA26C3 and bobcat #CF28AD came out
-- three near-identical magentas, coyote and turkey two cyans. Measured as
-- weighted RGB distance the closest pair scored 17 -- indistinguishable. That
-- was survivable for one homing arrow at a time and is useless for a map
-- showing every species at once, which is what surfaced it.
--
-- So the species WE ship get pinned colours, chosen for separation on a pale
-- map (closest pair now 109, a six-fold improvement) and checked pairwise
-- rather than by eye. The hash stays as the fallback, because an addon species
-- still has to get some colour and it cannot appear in a table shipped here.
local PINNED = {
    kwc_fox      = { 0.94, 0.24, 0.00 },   -- orange
    deer         = { 0.55, 0.37, 0.00 },   -- amber
    turkey       = { 0.42, 0.56, 0.00 },   -- olive
    kwc_squirrel = { 0.09, 0.64, 0.29 },   -- green
    kwc_coyote   = { 0.06, 0.64, 0.64 },   -- teal
    raccoon      = { 0.12, 0.44, 0.85 },   -- blue
    rabbit       = { 0.49, 0.23, 0.93 },   -- violet
    kwc_bobcat   = { 0.84, 0.14, 0.61 },   -- magenta
}

function L.colourFor(id)
    local pin = PINNED[id]
    if pin then return pin[1], pin[2], pin[3] end
    local h = 0
    for i = 1, #id do h = (h * 31 + string.byte(id, i)) % 360 end
    local function chan(off)
        local v = math.cos(((h + off) % 360) * math.pi / 180)
        return 0.55 + (0.40 * v)
    end
    return chan(0), chan(120), chan(240)
end

function L.pointAt(part)
    local player = getSpecificPlayer(0)
    if not player then return end

    L.clear()
    local label = L.labelFor(part.species)

    local x, y, dist, idx = L.findNearest(part, player:getX(), player:getY())
    if not x then
        HaloTextHelper.addBadText(player, "No " .. label .. " routes registered")
        return
    end

    L.target = { x = x, y = y, label = label, index = idx }
    local r, g, b = L.colourFor(part.species)
    L.arrow = getWorldMarkers():addPlayerHomingPoint(player, x, y, r, g, b, 1.0)

    HaloTextHelper.addText(player, string.format(
        "%s route #%d of %d -- %d tiles",
        label, idx - part.first + 1, part.count, math.floor(dist)))
end

-- Once you are on top of the route, swap the arrow for a ring on the ground,
-- because a homing arrow at two tiles' range just spins.
function L.update()
    if not L.target then return end
    local player = getSpecificPlayer(0)
    if not player then return end

    local dx = player:getX() - L.target.x
    local dy = player:getY() - L.target.y
    local dist = math.sqrt((dx * dx) + (dy * dy))

    if dist <= L.ARRIVE_DIST and not L.circle then
        local sq = getCell():getGridSquare(L.target.x, L.target.y, 0)
        if sq then
            L.circle = getWorldMarkers():addGridSquareMarker(
                sq, 0.95, 0.70, 0.20, true, 1)
            if L.circle.setScaleCircleTexture then
                L.circle:setScaleCircleTexture(true)
            end
        end
        if L.arrow then L.arrow:remove(); L.arrow = nil end
        HaloTextHelper.addGoodText(player, "On the route -- look around")
    end
end

-- Who gets the tools.
--
-- The old test was `isAdmin(player)`, which is wrong twice: isAdmin takes no
-- argument, and singleplayer has no admin concept at all, so it hid the menu
-- from exactly the person who owns the world. Vanilla's own pattern is
--
--     isDebugEnabled() or (isClient() and (isAdmin() or moderator))
--
-- ⚠️ ON BY DEFAULT IN SINGLEPLAYER, and that is a correction rather than a
-- preference. It was gated behind a sandbox option instead, which sounded
-- careful and was unusable: singleplayer sandbox settings live in `map_sand.bin`
-- and cannot be changed on a save that already exists. So the only way in was
-- -debug, which drags the whole vanilla debug menu along with it and covers the
-- screen. Forcing a player into debug mode to reach a menu of your own is not a
-- gate, it is a bug.
--
-- Alone, you own the world, and the menu costs one right-click to ignore. Anyone
-- who would rather not know where the deer are can turn Wildlife Admin Tools off
-- on a new save; the tooltip says so plainly.
local function mayUseTools() return KW.mayUseAdminTools() end

local function onContextMenu(playerIdx, context, worldobjects)
    local player = getSpecificPlayer(playerIdx)
    if not player then return end
    if not mayUseTools() then return end

    local parent = context:addOption("KnoxLife", worldobjects, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(parent, sub)

    -- Built from what is registered, so every species that has routes gets an
    -- entry, base or addon, without this file naming any of them. Sorted by
    -- rarity: the animal you are least likely to stumble on is the one you most
    -- want pointing at.
    local plan = L.plan()
    table.sort(plan, function(a, b)
        if a.count == b.count then return a.species < b.species end
        return a.count < b.count
    end)

    if #plan == 0 then
        sub:addOption("No routes registered yet", nil, nil)
    end
    for _, part in ipairs(plan) do
        local opt = sub:addOption(
            string.format("Nearest %s  (%d routes)",
                L.labelFor(part.species), part.count),
            nil, function() L.pointAt(part) end)
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip:setName(L.labelFor(part.species))
        tip.description = string.format(
            "Habitat: %s <LINE> %d of the map's routes <LINE> %s",
            part.pool, part.count,
            part.count < part.wanted
                and "the map could not supply as many as asked for"
                or "the whole share it asked for")
        opt.toolTip = tip
    end

    if L.target then
        sub:addOption("Clear marker", nil, function() L.clear() end)
    end

    -- Seeding an existing save. Singleplayer only for now: KW.reseedNear lives
    -- server-side, and on a dedicated server the client cannot call it without a
    -- command handler that does not exist yet. Hiding the option beats offering
    -- one that silently does nothing.
    if KW.reseedNear and not isClient() then
        local opt = sub:addOption("Seed wildlife around me", nil, function()
            local p = getSpecificPlayer(playerIdx)
            if not p then return end
            local placed, groups, already = KW.reseedNear(p:getX(), p:getY())
            if placed > 0 then
                HaloTextHelper.addGoodText(p, string.format(
                    "Seeded %d animals in %d groups", placed, groups))
            elseif already > 0 then
                HaloTextHelper.addText(p, "Already seeded here")
            else
                HaloTextHelper.addBadText(p, "No unseeded routes in range")
            end
        end)
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip:setName("Seed wildlife around me")
        tip.description =
            "Places family groups on this mod's routes within " ..
            tostring(KW.RESEED_RADIUS) .. " tiles. <LINE><LINE>" ..
            "For worlds that existed before the mod was installed: the game " ..
            "will not repopulate ground it has already processed, so those " ..
            "routes stay empty forever. This fills them in without a new save. " ..
            "<LINE><LINE>Each route is seeded once and remembered."
        opt.toolTip = tip
    end
end

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)
Events.OnPlayerUpdate.Add(L.update)
