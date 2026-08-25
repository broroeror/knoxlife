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
--
-- ⚠️ LAYOUT IS MEASURED, NEVER CONSTANT
--
-- This panel's first version placed its columns at fixed pixel offsets. At a
-- larger UI scale the strings outgrew the gaps and the header rendered as
-- "per sq mgroup", with every number sitting under the next column's label. The
-- data was right and the panel looked broken. Every column below is sized from
-- the widest string that will actually go in it -- see KW_UI.lua. If you add a
-- column, add it to the measuring pass too.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "KnoxLife/KW_UI"
require "KnoxLife/KW_MapOverlay"

KnoxLife = KnoxLife or {}
local KW = KnoxLife
local U = KW.UI

KW.Planner = ISPanel:derive("KWPlanner")
local P = KW.Planner

local FONT = UIFont.Small
local HEAD = UIFont.Medium
local SWATCH = 9

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

-- Column headings, in order. `right` means the cell is right-aligned, which is
-- what makes a column of numbers readable as a column.
local COLS = {
    { key = "label",   head = "Species" },
    { key = "density", head = "per sq mi", right = true },
    { key = "group",   head = "group",     right = true },
    { key = "routes",  head = "routes",    right = true },
    { key = "animals", head = "animals",   right = true },
}
local GAP = 18

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
            local r, g, b = 1, 1, 1
            if KW.Locator and KW.Locator.colourFor then
                r, g, b = KW.Locator.colourFor(part.species)
            end
            out[#out + 1] = {
                species = part.species,
                label = (KW.Locator and KW.Locator.labelFor and KW.Locator.labelFor(part.species))
                        or part.species,
                got = part.count or 0,
                wanted = part.wanted or 0,
                group = group,
                animals = n,
                pool = part.pool,
                r = r, g = g, b = b,
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

--- Turn the plan into the exact strings each cell will show.
--
-- Formatting happens HERE rather than in render, because the column widths are
-- measured from these strings and a cell formatted differently at draw time
-- would not fit the space measured for it.
local function cellsFor(r)
    return {
        label   = r.label,
        density = string.format("%.2f", r.group > 0 and (r.animals / 88.83) or 0),
        group   = string.format("%.1f", r.group),
        routes  = r.wanted > r.got and (r.got .. " of " .. r.wanted) or tostring(r.got),
        animals = tostring(r.animals),
    }
end

function P:recompute()
    self.result = planFor(self:settingsFromDials()) or { rows = {}, animals = 0, routes = 0 }
    local res = self.result

    self.maxAnimals = 1
    for _, r in ipairs(res.rows) do
        r.cells = cellsFor(r)
        if r.animals > self.maxAnimals then self.maxAnimals = r.animals end
    end
    self.totals = {
        label   = "Total",
        density = string.format("%.1f", res.animals / 88.83),
        group   = "",
        routes  = tostring(res.routes),
        animals = tostring(res.animals),
    }

    self.note = "No species is route-limited here. Group Size changes herd size, not the total."
    local capped = 0
    for _, r in ipairs(res.rows) do if r.wanted > r.got then capped = capped + 1 end end
    if capped > 0 then
        self.note = capped .. " species want more routes than the map can supply -- "
                 .. "raising density further will not add those animals."
    end

    self:layout()
end

--- Size every column to the widest string that will go in it, then size the
--- panel to the columns. Called on every recompute: the strings change.
function P:layout()
    local strings = {}
    for _, c in ipairs(COLS) do strings[c.key] = { c.head } end
    for _, r in ipairs(self.result.rows) do
        for _, c in ipairs(COLS) do
            table.insert(strings[c.key], r.cells[c.key])
        end
    end
    for _, c in ipairs(COLS) do table.insert(strings[c.key], self.totals[c.key]) end

    self.fh = U.h(FONT)
    self.row = self.fh + 9

    local x = U.PAD + SWATCH + 8          -- room for the colour swatch
    for _, c in ipairs(COLS) do
        c.x = x
        c.w = U.widest(FONT, strings[c.key])
        x = x + c.w + GAP
    end
    self.barX = x
    local barW = 64

    -- The panel is at least as wide as its widest single line -- the dials, the
    -- title, and the footnote are all longer than the table on a narrow plan.
    local dialW = 0
    for _, d in ipairs(DIALS) do
        dialW = math.max(dialW, U.widest(FONT, d.names) + 34, U.w(FONT, d.label))
    end
    self.dialW = dialW
    local need = math.max(
        x + barW + U.PAD,
        U.PAD * 2 + dialW * 3 + 20,
        U.PAD * 2 + U.w(FONT, self.note),
        U.PAD * 2 + U.w(HEAD, "KnoxLife -- population planner") + 110)
    self:setWidth(math.ceil(need))

    local headH = U.h(HEAD)
    self.dialTop = U.PAD + headH + 10 + self.fh + 4
    self.tableTop = self.dialTop + self.row + U.PAD + self.fh + 8
    self:setHeight(math.ceil(
        self.tableTop + self.row * (#self.result.rows + 2) + self.fh + U.PAD * 2))

    if self.combos then
        local cw = math.floor((self:getWidth() - U.PAD * 2 - 20) / 3)
        local cx = U.PAD
        for _, c in ipairs(self.combos) do
            c:setX(cx); c:setY(self.dialTop); c:setWidth(cw); c:setHeight(self.row)
            cx = cx + cw + 10
        end
    end
    if self.closeBtn then self.closeBtn:setX(self:getWidth() - U.PAD - 90) end
    if self.mapBtn then self.mapBtn:setX(self:getWidth() - U.PAD - 90 - 8 - 104) end
end

function P:createChildren()
    ISPanel.createChildren(self)
    U.skin(self)
    self.combos = {}

    local fh = U.h(FONT)
    for i, d in ipairs(DIALS) do
        local c = ISComboBox:new(U.PAD, 0, 120, fh + 9, self, function() self:recompute() end)
        c:initialise()
        for _, n in ipairs(d.names) do c:addOption(n) end
        -- Open on what the world is actually running, so the first thing an
        -- admin sees is their own settings rather than a default they never chose.
        local live = KW.getOption and KW.getOption(d.key, d.default) or d.default
        c.selected = math.max(1, math.min(#d.names, math.floor(tonumber(live) or d.default)))
        self:addChild(c)
        self.combos[i] = c
    end

    self.closeBtn = ISButton:new(0, U.PAD, 90, fh + 9, "Close", self,
        function() self:removeFromUIManager(); P.instance = nil end)
    self.closeBtn:initialise(); self.closeBtn:instantiate()
    if self.closeBtn.enableCancelColor then self.closeBtn:enableCancelColor() end
    self:addChild(self.closeBtn)

    -- The table says how many. The map says where. They are the same question.
    self.mapBtn = ISButton:new(0, U.PAD, 104, fh + 9, "Show on map", self,
        function() KW.MapOverlay.show(self.playerNum or 0) end)
    self.mapBtn:initialise(); self.mapBtn:instantiate()
    self:addChild(self.mapBtn)

    self:recompute()
end

function P:render()
    ISPanel.render(self)
    local res = self.result
    if not res then return end
    local W, fh, row = self:getWidth(), self.fh, self.row

    self:drawText("KnoxLife -- population planner", U.PAD, U.PAD - 2,
                  U.TEXT[1], U.TEXT[2], U.TEXT[3], 1, HEAD)

    -- Dial labels sit ABOVE their combo boxes, in the gap reserved for them.
    -- They used to be drawn into the same band as the combos and were half
    -- hidden behind them.
    local cx = U.PAD
    local cw = math.floor((W - U.PAD * 2 - 20) / 3)
    for _, d in ipairs(DIALS) do
        self:drawText(d.label, cx, self.dialTop - fh - 4, U.DIM[1], U.DIM[2], U.DIM[3], 1, FONT)
        cx = cx + cw + 10
    end

    local function cell(text, c, y, r, g, b)
        if c.right then
            self:drawTextRight(text, c.x + c.w, y, r, g, b, 1, FONT)
        else
            self:drawText(text, c.x, y, r, g, b, 1, FONT)
        end
    end

    local y = self.tableTop - row
    for _, c in ipairs(COLS) do
        cell(c.head, c, y, U.DIM[1], U.DIM[2], U.DIM[3])
    end
    y = y + row - 2
    self:drawRect(U.PAD, y, W - U.PAD * 2, 1, U.RULE[1], U.RULE[2], U.RULE[3], U.RULE[4])
    y = y + 6

    for _, r in ipairs(res.rows) do
        local capped = r.wanted > r.got
        local cr, cg, cb = U.TEXT[1], U.TEXT[2], U.TEXT[3]
        if capped then cr, cg, cb = U.WARN[1], U.WARN[2], U.WARN[3] end

        -- The swatch is the tie to the map overlay: same colour, same species.
        U.swatch(self, U.PAD, y + math.floor((fh - SWATCH) / 2), SWATCH, r.r, r.g, r.b)

        for _, c in ipairs(COLS) do
            local dim = (c.key == "density" or c.key == "group")
            if dim and not capped then
                cell(r.cells[c.key], c, y, U.DIM[1], U.DIM[2], U.DIM[3])
            else
                cell(r.cells[c.key], c, y, cr, cg, cb)
            end
        end

        local bw = math.max(2, math.floor(r.animals / self.maxAnimals * 56))
        self:drawRect(self.barX, y + 4, bw, fh - 6, capped and 0.85 or 0.7, r.r, r.g, r.b)
        y = y + row
    end

    y = y + 4
    self:drawRect(U.PAD, y, W - U.PAD * 2, 1, U.RULE[1], U.RULE[2], U.RULE[3], U.RULE[4])
    y = y + 8
    for _, c in ipairs(COLS) do cell(self.totals[c.key], c, y, 1, 1, 1) end
    y = y + row

    self:drawText(self.note, U.PAD, y, U.DIM[1], U.DIM[2], U.DIM[3], 1, FONT)
end

--- @param playerNum which split-screen player asked. Threaded through rather
---        than assumed 0, because "Show on map" opens THAT player's map.
function P.open(playerNum)
    if P.instance then P.instance:removeFromUIManager(); P.instance = nil end
    local ui = P:new(140, 110, 640, 300)
    ui.playerNum = playerNum or 0
    ui.moveWithMouse = true
    ui:initialise(); ui:instantiate()
    ui:addToUIManager()
    P.instance = ui
    return ui
end

return P
