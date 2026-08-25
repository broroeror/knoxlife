-- Knox Life -- "what will these settings actually give me?"
--
-- The population model is deterministic, so the answer is computable rather than
-- something an admin has to discover by cranking a dial, starting a world and
-- walking around. This panel computes it.
--
-- WHY IT MATTERS MORE THAN IT LOOKS
--
-- Two behaviours in the model are genuinely counter-intuitive, and both of them
-- read as "the mod is broken" if you meet them by experiment:
--
--   Group Size barely moves the total. Routes are density x habitat / group
--   size, so a bigger family means proportionally fewer families -- the same
--   animals in fewer, larger herds. An admin who doubles it expecting twice the
--   wildlife gets the same wildlife, and reasonably concludes nothing happened.
--
--   Asking is not getting. Each species draws from a baked route pool. Past the
--   point where it wants more routes than the map has places to put them, the
--   surplus is silently dropped and turning density up does nothing at all.
--
-- Both are visible here at a glance and invisible in play.
--
-- ONE COPY OF THE MATHS
--
-- This does NOT reimplement the model. It sets KW.preview -- a stand-in for the
-- sandbox, honoured by KW.pickFromScale, which every formula already routes
-- through -- and then calls the real KW.allocateRoutes(). So the planner cannot
-- drift from the spawner: there is only one implementation and this is a caller
-- of it. See KW.withPreview in KW_Core.lua.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"

KnoxLife = KnoxLife or {}
local KW = KnoxLife

KW.Planner = ISPanel:derive("KWPlanner")
local P = KW.Planner

local FONT = UIFont.Small
local FH = getTextManager():getFontHeight(FONT)
local PAD = 12
local ROW = FH + 9
local W = 640

-- Column x-offsets. Named because a table drawn with drawText needs its columns
-- in one place or they drift apart the first time a label changes.
local COL = { name = 0, density = 210, group = 290, routes = 375, animals = 500, bar = 575 }

-- Labels for the three dials. The scales themselves live in KW_Core -- these are
-- only the words, and the index is what gets handed to KW.preview.
local DIALS = {
    { key = "RouteDensity", label = "Wildlife Density", default = 3,
      names = { "Quarter", "Half", "Realistic", "One and a half", "Double" } },
    { key = "GroupSize", label = "Group Size", default = 3,
      names = { "Half", "Three quarters", "Normal", "Larger", "Much larger" } },
    { key = "SpeciesMix", label = "Species Mix", default = 1,
      names = { "Realistic", "Balanced", "Deer-heavy" } },
}

--- The plan for one set of dial positions, or for the live world when nil.
--
-- Everything here comes back from the real allocator. `count` is what the map
-- could supply, `wanted` is what the density asked for, and the gap between them
-- is the thing this panel exists to make visible.
local function planFor(settings)
    local run = function()
        if not KW.allocateRoutes then return {} end
        local plan = KW.allocateRoutes()
        if type(plan) ~= "table" then return {} end
        local out, animals, routes = {}, 0, 0
        for _, part in ipairs(plan) do
            local group = KW.meanGroupSize(part.species) or 0
            local n = math.floor((part.count or 0) * group + 0.5)
            animals = animals + n
            routes = routes + (part.count or 0)
            out[#out + 1] = {
                species = part.species,
                label = (KW.Locator and KW.Locator.labelFor and KW.Locator.labelFor(part.species))
                        or part.species,
                got = part.count or 0,
                wanted = part.wanted or 0,
                group = group,
                animals = n,
                pool = part.pool,
            }
        end
        table.sort(out, function(a, b) return a.animals > b.animals end)
        return { rows = out, animals = animals, routes = routes }
    end
    if settings then return KW.withPreview(settings, run) end
    return run()
end

function P.settingsFromDials(self)
    local s = {}
    for i, d in ipairs(DIALS) do
        s[d.key] = self.combos[i] and self.combos[i].selected or d.default
    end
    return s
end

function P:recompute()
    self.result = planFor(self:settingsFromDials()) or { rows = {}, animals = 0, routes = 0 }
    self.maxAnimals = 1
    for _, r in ipairs(self.result.rows) do
        if r.animals > self.maxAnimals then self.maxAnimals = r.animals end
    end
end

function P:createChildren()
    ISPanel.createChildren(self)
    self.combos = {}

    local x = PAD
    local cw = math.floor((W - PAD * 2 - 20) / 3)
    for i, d in ipairs(DIALS) do
        local c = ISComboBox:new(x, PAD + FH + 6, cw, ROW, self, function() self:recompute() end)
        c:initialise()
        for _, n in ipairs(d.names) do c:addOption(n) end
        -- Open on what the world is actually running, so the first thing an
        -- admin sees is their own settings rather than a default they never chose.
        local live = KW.getOption and KW.getOption(d.key, d.default) or d.default
        c.selected = math.max(1, math.min(#d.names, math.floor(tonumber(live) or d.default)))
        self:addChild(c)
        self.combos[i] = c
        x = x + cw + 10
    end

    self.tableTop = PAD + FH + 6 + ROW + PAD + FH + 8

    local close = ISButton:new(W - PAD - 90, PAD, 90, ROW, "Close", self,
        function() self:removeFromUIManager(); P.instance = nil end)
    close:initialise(); close:instantiate()
    if close.enableCancelColor then close:enableCancelColor() end
    self:addChild(close)

    self:recompute()
    self:setHeight(self.tableTop + ROW * (#self.result.rows + 3) + PAD * 2)
end

function P:render()
    ISPanel.render(self)
    local res = self.result
    if not res then return end

    self:drawText("KnoxLife -- population planner", PAD, PAD - 2, 1, 1, 1, 1, UIFont.Medium)

    -- Dial labels sit above their combo boxes.
    local x, cw = PAD, math.floor((W - PAD * 2 - 20) / 3)
    for _, d in ipairs(DIALS) do
        self:drawText(d.label, x, PAD + FH - 4, 0.66, 0.68, 0.62, 1, FONT)
        x = x + cw + 10
    end

    local y = self.tableTop - ROW
    local function head(t, cx) self:drawText(t, PAD + cx, y, 0.6, 0.62, 0.56, 1, FONT) end
    head("Species", COL.name); head("per sq mi", COL.density); head("group", COL.group)
    head("routes", COL.routes); head("animals", COL.animals)
    y = y + ROW - 2
    self:drawRect(PAD, y, W - PAD * 2, 1, 0.35, 1, 1, 1)
    y = y + 6

    for _, r in ipairs(res.rows) do
        local capped = r.wanted > r.got
        local cr, cg, cb = 0.88, 0.89, 0.85
        if capped then cr, cg, cb = 0.92, 0.72, 0.36 end

        self:drawText(r.label, PAD + COL.name, y, cr, cg, cb, 1, FONT)
        self:drawText(string.format("%.2f", r.group > 0 and (r.animals / 88.83) or 0),
            PAD + COL.density, y, 0.7, 0.72, 0.66, 1, FONT)
        self:drawText(string.format("%.1f", r.group), PAD + COL.group, y, 0.7, 0.72, 0.66, 1, FONT)

        local routeText = tostring(r.got)
        if capped then routeText = routeText .. " of " .. tostring(r.wanted) end
        self:drawText(routeText, PAD + COL.routes, y, cr, cg, cb, 1, FONT)
        self:drawText(tostring(r.animals), PAD + COL.animals, y, cr, cg, cb, 1, FONT)

        local bw = math.max(2, math.floor(r.animals / self.maxAnimals * 50))
        self:drawRect(PAD + COL.bar, y + 4, bw, FH - 6,
            0.85, capped and 0.66 or 0.49, capped and 0.42 or 0.57, capped and 0.21 or 0.41)
        y = y + ROW
    end

    y = y + 4
    self:drawRect(PAD, y, W - PAD * 2, 1, 0.35, 1, 1, 1)
    y = y + 8
    self:drawText("Total", PAD + COL.name, y, 1, 1, 1, 1, FONT)
    self:drawText(string.format("%.1f", res.animals / 88.83), PAD + COL.density, y, 1, 1, 1, 1, FONT)
    self:drawText(tostring(res.routes), PAD + COL.routes, y, 1, 1, 1, 1, FONT)
    self:drawText(tostring(res.animals), PAD + COL.animals, y, 1, 1, 1, 1, FONT)
    y = y + ROW

    local capped = 0
    for _, r in ipairs(res.rows) do if r.wanted > r.got then capped = capped + 1 end end
    local note
    if capped > 0 then
        note = capped .. " species want more routes than the map can supply -- "
             .. "raising density further will not add those animals."
    else
        note = "No species is route-limited here. Group Size changes herd size, not the total."
    end
    self:drawText(note, PAD, y, 0.62, 0.64, 0.58, 1, FONT)
end

function P.open()
    if P.instance then P.instance:removeFromUIManager(); P.instance = nil end
    local ui = P:new(140, 110, W, 300)
    ui.moveWithMouse = true
    ui:initialise(); ui:instantiate()
    ui:addToUIManager()
    P.instance = ui
    return ui
end

return P
