-- Knox Life -- where the animals actually are, drawn on the world map.
--
-- The planner answers "how many will I get?". This answers "and WHERE?", which
-- is the other half of the same question and the one a table cannot show. An
-- admin picking a density wants to know whether the north woods are empty,
-- whether two species overlap on the same ground, and whether the map even has
-- habitat where they expect it.
--
-- WHAT A DOT IS
--
-- One migration route, drawn at its midpoint. Not one animal, and not a spawn
-- point in the sense of a fixed pad: a route is a polyline a herd walks, and
-- the group that owns it can be anywhere along it. The midpoint is the honest
-- single-pixel answer to "where is this herd", and it is the SAME midpoint the
-- locator arrow homes to (KW_Locator.midpointOf) so the map and the arrow can
-- never disagree about where a route is.
--
-- ONE COPY OF THE ALLOCATION, AGAIN
--
-- The dots come from KW.allocateRoutes(), the same call the planner and the
-- server make. Nothing here decides what is registered; it reads the decision.
-- That matters because a species gets a SLICE of a shared pool -- first..first
-- +count-1 -- and a plausible-looking "draw every route in the pool" would show
-- routes nobody registered, which is precisely the bug KW_Locator once had.
--
-- WHY IT CACHES
--
-- A full map is ~2,500 routes. Recomputing midpoints every frame would be 2,500
-- table walks at 60fps for data that only changes when the allocation changes,
-- so the world positions are built once into a flat list and only the world ->
-- screen conversion happens per frame.

require "ISUI/ISPanel"
require "ISUI/Maps/ISWorldMap"

KnoxLife = KnoxLife or {}
local KW = KnoxLife

KW.MapOverlay = KW.MapOverlay or {}
local M = KW.MapOverlay

M.enabled = false
M.hidden = {}           -- species id -> true when the legend has it switched off
M.points = nil          -- flat cache: { {x, y, id}, ... }
M.byS = nil             -- species id -> { label, count, r, g, b, capped }

-- Past this zoom the dots become the routes themselves. Below it a polyline is
-- shorter than a pixel and 15,000 sub-pixel line segments cost a lot to say
-- nothing. getZoomF grows as you zoom IN.
local ROUTE_ZOOM = 5.5

--- Rebuild the cache from the live allocation. Cheap enough to call on open.
function M.build()
    M.points, M.byS = {}, {}
    if not (KW.allocateRoutes and KW.Routes) then return end

    local ok, plan = pcall(KW.allocateRoutes)
    if not ok or type(plan) ~= "table" then
        KW.log("map overlay: allocateRoutes failed: " .. tostring(plan))
        return
    end

    local L = KW.Locator
    for _, part in ipairs(plan) do
        local pool = KW.Routes[part.pool]
        if pool then
            local r, g, b = L.colourFor(part.species)
            M.byS[part.species] = {
                label  = L.labelFor(part.species),
                count  = part.count or 0,
                wanted = part.wanted or 0,
                r = r, g = g, b = b,
            }
            local last = (part.first or 1) + (part.count or 0) - 1
            for i = part.first or 1, last do
                local route = pool[i]
                -- A slice can outrun a pool an addon shrank underneath us.
                if route and route.follow then
                    local x, y = L.midpointOf(route.follow)
                    if x then
                        M.points[#M.points + 1] = { x = x, y = y, id = part.species,
                                                    follow = route.follow }
                    end
                end
            end
        end
    end
end

function M.setEnabled(on)
    M.enabled = on and true or false
    if M.enabled and not M.points then M.build() end
end

function M.toggleSpecies(id)
    M.hidden[id] = not M.hidden[id] or nil
end

--- Draw the dots over an ISWorldMap. Called from the render wrap below.
function M.draw(map)
    if not (M.enabled and M.points and map and map.mapAPI) then return end

    local api = map.mapAPI
    local zoom = api:getZoomF() or 0
    local routes = zoom >= ROUTE_ZOOM

    -- Dot size tracks zoom so the map reads as dense-vs-sparse rather than as a
    -- solid wash at every scale.
    local size = 3
    if zoom >= 3 then size = 4 end
    if zoom >= ROUTE_ZOOM then size = 5 end
    local half = size / 2

    local w, h = map:getWidth(), map:getHeight()
    for _, p in ipairs(M.points) do
        if not M.hidden[p.id] then
            local c = M.byS[p.id]
            if c then
                local ux = api:worldToUIX(p.x, p.y)
                local uy = api:worldToUIY(p.x, p.y)
                -- Cull offscreen: at low zoom most of the map is not on screen,
                -- and drawing there is pure cost.
                if ux > -16 and uy > -16 and ux < w + 16 and uy < h + 16 then
                    if routes and p.follow then
                        local f = p.follow
                        for i = 1, #f - 3, 2 do
                            map:drawLine2(
                                api:worldToUIX(f[i], f[i + 1]),
                                api:worldToUIY(f[i], f[i + 1]),
                                api:worldToUIX(f[i + 2], f[i + 3]),
                                api:worldToUIY(f[i + 2], f[i + 3]),
                                0.75, c.r, c.g, c.b)
                        end
                    end
                    -- A dark seat under every dot, so a pale species still
                    -- reads on snow, sand or a lit road.
                    map:drawRect(ux - half - 1, uy - half - 1, size + 2, size + 2,
                                 0.55, 0, 0, 0)
                    map:drawRect(ux - half, uy - half, size, size, 1.0, c.r, c.g, c.b)
                end
            end
        end
    end
end

-- Wrap the vanilla render rather than replacing it. Guarded so a second load of
-- this file cannot stack two wrappers and draw everything twice.
if not M.wrapped then
    M.wrapped = true
    local baseRender = ISWorldMap.render
    function ISWorldMap:render()
        baseRender(self)
        local ok, err = pcall(M.draw, self)
        -- A throw here would land once per frame, forever, and take the map's
        -- own render down with it. Report once and switch off instead.
        if not ok then
            M.enabled = false
            KW.log("map overlay disabled after an error: " .. tostring(err))
        end
    end
end

-- ---------------------------------------------------------------------------
-- The legend, which is also the control surface.
--
-- A colour-coded map is unreadable without a key, and the key is the natural
-- place to put "show only deer". So it is one panel: swatch, name, how many
-- routes, and clicking a row hides or shows that species.

require "ISUI/ISButton"
require "KnoxLife/KW_UI"
local U = KW.UI

KW.MapLegend = ISPanel:derive("KWMapLegend")
local G = KW.MapLegend
local FONT = UIFont.Small
local HEAD = UIFont.Medium
local SWATCH = 10

function G:rebuild()
    self.rows = {}
    for id, c in pairs(M.byS or {}) do
        self.rows[#self.rows + 1] = {
            id = id, label = c.label, count = c.count, wanted = c.wanted,
            r = c.r, g = c.g, b = c.b,
        }
    end
    table.sort(self.rows, function(a, b) return a.count > b.count end)

    self.fh = U.h(FONT)
    self.row = self.fh + 8

    local names, counts = {}, {}
    for _, r in ipairs(self.rows) do
        names[#names + 1] = r.label
        counts[#counts + 1] = r.wanted > r.count
            and (r.count .. " of " .. r.wanted) or tostring(r.count)
        r.countText = counts[#counts]
    end
    self.nameW = math.max(U.widest(FONT, names), U.w(FONT, "Species"))
    self.countW = math.max(U.widest(FONT, counts), U.w(FONT, "routes"))

    self.headH = U.h(HEAD)
    self.tableTop = U.PAD + self.headH + 8 + self.fh + 6
    local w = U.PAD * 2 + SWATCH + 8 + self.nameW + 18 + self.countW
    w = math.max(w, U.PAD * 2 + U.w(HEAD, "Knox: routes on the map"),
                    U.PAD * 2 + U.w(FONT, "click a row to hide that species"),
                    U.PAD * 2 + U.btnW(FONT, "Show all") + 10 + U.btnW(FONT, "Close", 70))
    self:setWidth(math.ceil(w))
    self:setHeight(math.ceil(self.tableTop + self.row * #self.rows
                             + self.fh + 10 + self.row + U.PAD))
    if self.closeBtn then
        self.closeBtn:setY(self:getHeight() - U.PAD - self.row)
        local cw = U.btnW(FONT, "Close", 70)
        self.closeBtn:setWidth(cw)
        self.closeBtn:setX(self:getWidth() - U.PAD - cw)
    end
    if self.allBtn then self.allBtn:setY(self:getHeight() - U.PAD - self.row) end
end

function G:createChildren()
    ISPanel.createChildren(self)
    U.skin(self)
    local fh = U.h(FONT)

    self.allBtn = ISButton:new(U.PAD, 0, U.btnW(FONT, "Show all"), fh + 8, "Show all", self,
        function() M.hidden = {} end)
    self.allBtn:initialise(); self.allBtn:instantiate()
    self:addChild(self.allBtn)

    self.closeBtn = ISButton:new(0, 0, U.btnW(FONT, "Close", 70), fh + 8, "Close", self,
        function() M.hide() end)
    self.closeBtn:initialise(); self.closeBtn:instantiate()
    if self.closeBtn.enableCancelColor then self.closeBtn:enableCancelColor() end
    self:addChild(self.closeBtn)

    self:rebuild()
end

-- Toggling happens on mouse UP, and only when the pointer did not travel: the
-- panel is draggable, and ISPanel implements dragging out of onMouseDown, so
-- claiming the down event would make the legend impossible to move.
function G:onMouseUp(x, y)
    local moved = self.downX and (math.abs(x - self.downX) > 3 or math.abs(y - self.downY) > 3)
    if not moved and self.rows then
        local i = math.floor((y - self.tableTop) / self.row) + 1
        if i >= 1 and i <= #self.rows then
            M.toggleSpecies(self.rows[i].id)
        end
    end
    return ISPanel.onMouseUp(self, x, y)
end

function G:render()
    ISPanel.render(self)
    if not self.rows then return end
    local W, fh, row = self:getWidth(), self.fh, self.row

    self:drawText("Knox: routes on the map", U.PAD, U.PAD - 2,
                  U.TEXT[1], U.TEXT[2], U.TEXT[3], 1, HEAD)

    local y = self.tableTop - fh - 6
    self:drawText("Species", U.PAD + SWATCH + 8, y, U.DIM[1], U.DIM[2], U.DIM[3], 1, FONT)
    self:drawTextRight("routes", W - U.PAD, y, U.DIM[1], U.DIM[2], U.DIM[3], 1, FONT)
    y = y + fh + 3
    self:drawRect(U.PAD, y, W - U.PAD * 2, 1, U.RULE[1], U.RULE[2], U.RULE[3], U.RULE[4])

    y = self.tableTop
    for _, r in ipairs(self.rows) do
        local off = M.hidden[r.id]
        if self:isMouseOver() then
            local my = self:getMouseY()
            if my >= y and my < y + row then
                self:drawRect(U.PAD - 4, y - 2, W - U.PAD * 2 + 8, row, 0.16, 1, 1, 1)
            end
        end
        -- A hidden species keeps its place and its colour, hollowed out: the
        -- list must not reorder or shrink as you click through it.
        local sy = y + math.floor((fh - SWATCH) / 2)
        if off then
            self:drawRectBorder(U.PAD, sy, SWATCH, SWATCH, 0.75, r.r, r.g, r.b)
        else
            U.swatch(self, U.PAD, sy, SWATCH, r.r, r.g, r.b)
        end
        local tr, tg, tb = U.TEXT[1], U.TEXT[2], U.TEXT[3]
        if off then tr, tg, tb = U.DIM[1] * 0.7, U.DIM[2] * 0.7, U.DIM[3] * 0.7 end
        self:drawText(r.label, U.PAD + SWATCH + 8, y, tr, tg, tb, 1, FONT)
        local cr, cg, cb = tr, tg, tb
        if not off and r.wanted > r.count then cr, cg, cb = U.WARN[1], U.WARN[2], U.WARN[3] end
        self:drawTextRight(r.countText, W - U.PAD, y, cr, cg, cb, 1, FONT)
        y = y + row
    end

    y = y + 6
    self:drawText("click a row to hide that species", U.PAD, y,
                  U.DIM[1] * 0.85, U.DIM[2] * 0.85, U.DIM[3] * 0.85, 1, FONT)
end

function G.open()
    if G.instance then G.instance:removeFromUIManager(); G.instance = nil end
    local ui = G:new(24, 90, 260, 200)
    ui.moveWithMouse = true
    ui:initialise(); ui:instantiate()
    ui:addToUIManager()
    -- The world map is full-screen and added after us otherwise. This is the
    -- same mechanism vanilla uses for its own dialogs over the map
    -- (ISWorldMap.lua:998).
    ui:setAlwaysOnTop(true)
    ui:bringToTop()
    G.instance = ui
    return ui
end

--- Open the map with the overlay on. The entry point everything else calls.
function M.show(playerNum)
    playerNum = playerNum or 0
    -- ShowWorldMap returns silently when the sandbox has the map switched off,
    -- which would make this button look broken in exactly the way this whole
    -- session was spent fixing. Say so instead.
    if not ISWorldMap.IsAllowed() then
        local p = getSpecificPlayer(playerNum)
        if p and HaloTextHelper then
            HaloTextHelper.addBadText(p, "This server has the world map disabled")
        end
        KW.log("map overlay: SandboxVars.Map.AllowWorldMap is off; nothing to draw on")
        return false
    end
    M.build()
    M.setEnabled(true)
    ISWorldMap.ShowWorldMap(playerNum)
    G.open()
    if G.instance then G.instance:rebuild() end
    return true
end

function M.hide()
    M.setEnabled(false)
    if G.instance then G.instance:removeFromUIManager(); G.instance = nil end
end

return M
