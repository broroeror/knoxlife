-- Knox Life -- one section in the game's debug menu.
--
-- Everything this mod family can do for testing lives here, in one place,
-- instead of being spread across a right-click menu and a handful of sandbox
-- switches you can only reach by starting a new save. The right-click locator
-- still exists for admins in normal play; this is the version you want while
-- actually testing, because it also reports what was registered and lets you
-- flip runtime-only switches without touching the save.
--
-- Add-ons do not need their own entry. The species list is built from whatever
-- registered routes, so installing the Bobcat add-on makes a bobcat row appear
-- here with no code on its side, and the Overkill row appears only if that mod
-- is loaded.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "DebugUIs/DebugMenu/ISDebugMenu"
require "KnoxLife/KW_Planner"

KnoxLife = KnoxLife or {}
local KW = KnoxLife

KW.DebugUI = ISPanel:derive("KWDebugUI")
local UI = KW.DebugUI

local FONT_HGT = getTextManager():getFontHeight(UIFont.Small)
local PAD = 10
local ROW = FONT_HGT + 8

-- Sandbox values are read live on every call by both KW.getOption and
-- Overkill's own opt(), so writing straight into SandboxVars takes effect
-- immediately. It is deliberately NOT persisted: this is a testing toggle, and
-- a debug menu that silently rewrites someone's save settings would be worse
-- than no toggle at all.
local function runtimeSet(block, key, value)
    if not SandboxVars then return false end
    local vars = SandboxVars[block]
    if vars == nil then return false end
    vars[key] = value
    return true
end

local function runtimeGet(block, key, fallback)
    if not SandboxVars then return fallback end
    local vars = SandboxVars[block]
    if vars == nil then return fallback end
    local v = vars[key]
    if v == nil then return fallback end
    return v
end

local function say(msg)
    local p = getSpecificPlayer(0)
    if p and HaloTextHelper then HaloTextHelper.addGoodText(p, msg) end
    print("[KnoxLife][debug] " .. tostring(msg))
end

-- What was actually registered, rather than what the settings asked for. The
-- gap between the two is the single most useful thing to see while testing:
-- a species can ask for 40 routes and get 6 because the map has nowhere to put
-- them, and nothing else in the game will tell you that happened.
function UI.report()
    local L = KW.Locator
    print("[KnoxLife][debug] ---- population report ----")
    print(string.format("[KnoxLife][debug] version %s, api %s",
        tostring(KW.VERSION), tostring(KW.API_VERSION)))
    local plan = (L and L.plan and L.plan()) or {}
    if #plan == 0 then
        print("[KnoxLife][debug] no routes registered yet")
    end
    local total = 0
    for _, part in ipairs(plan) do
        total = total + (part.count or 0)
        print(string.format("[KnoxLife][debug]   %-14s pool=%-6s routes=%-5d asked=%-5d %s",
            tostring(part.species), tostring(part.pool),
            part.count or 0, part.wanted or 0,
            (part.count or 0) < (part.wanted or 0) and "<- map could not supply" or ""))
    end
    print(string.format("[KnoxLife][debug] %d species, %d routes total", #plan, total))
    for _, key in ipairs({"RouteDensity", "SpeciesMix", "GroupSize", "WildlifeRecovery",
                          "RecoveryRate", "WildTurkey", "WildRaccoon", "RebalanceFarms"}) do
        print(string.format("[KnoxLife][debug]   setting %-18s = %s",
            key, tostring(runtimeGet("KnoxLife", key, "<unset>"))))
    end
    say(string.format("Report printed: %d species, %d routes", #plan, total))
end

-- One row per thing you can do. Built fresh every time the panel opens, because
-- route counts and the installed add-on set both change under it.
function UI.rows()
    local rows = {}
    local L = KW.Locator
    local plan = (L and L.plan and L.plan()) or {}
    table.sort(plan, function(a, b)
        if a.count == b.count then return a.species < b.species end
        return a.count < b.count
    end)

    for _, part in ipairs(plan) do
        local label = string.format("Point me at the nearest %s  (%d routes)",
            L.labelFor(part.species), part.count)
        rows[#rows + 1] = { label = label, fn = function() L.pointAt(part) end }
    end
    if #plan == 0 then
        rows[#rows + 1] = { label = "No routes registered yet", fn = nil }
    end

    rows[#rows + 1] = { label = "Clear the marker", fn = function()
        if L and L.clear then L.clear() end
        say("Marker cleared")
    end }

    -- Seeding lives server-side. On a dedicated client there is no command
    -- handler for it, so offer nothing rather than a button that does nothing.
    if KW.reseedNear and not (isClient and isClient()) then
        rows[#rows + 1] = { label = "Seed wildlife around me", fn = function()
            local p = getSpecificPlayer(0)
            if not p then return end
            local placed, groups, already = KW.reseedNear(p:getX(), p:getY())
            if placed and placed > 0 then
                say(string.format("Seeded %d animals in %d groups", placed, groups or 0))
            elseif already and already > 0 then
                say(string.format("Nothing seeded -- %d already nearby", already))
            else
                say("Nothing seeded -- no suitable ground here")
            end
        end }
    end

    -- Same server-side constraint as seeding, and for the same documented
    -- reason (KW_Reseed.lua:64) -- an animal spawned on an MP client renders and
    -- walks but can never be hurt, because only the server allocates the network
    -- id a hit packet needs. Say so rather than hiding the row: someone looking
    -- for this button needs to know it exists and why it is not here.
    if KW.spawnJuvenilesAt then
        if isClient and isClient() then
            -- On a server the right-click admin menu is the route -- it needs no
            -- -debug, and it can ask the server to do the spawning, which a
            -- client-side button structurally cannot. See KW_AdminMenu.lua.
            rows[#rows + 1] = { label = "Juveniles: right-click the ground as admin instead",
                                fn = nil }
        else
            rows[#rows + 1] = { label = "Spawn one of each juvenile next to me", fn = function()
                local p = getSpecificPlayer(0)
                if not p then return end
                local placed, missed = KW.spawnJuvenilesAt(p:getX(), p:getY())
                if #missed == 0 then
                    say(string.format("Spawned %d juveniles", placed))
                else
                    say(string.format("Spawned %d, failed: %s",
                        placed, table.concat(missed, ", ")))
                end
            end }
        end
    end

    -- The planner supersedes the console report for most purposes: same numbers,
    -- but it also answers "what if I changed the dials?", which the report cannot.
    -- The report stays because it prints, and a printed thing can be pasted into
    -- an issue.
    if KW.Planner then
        rows[#rows + 1] = { label = "Population planner (what will these settings give?)",
                            fn = function() KW.Planner.open() end }
    end
    rows[#rows + 1] = { label = "Print population report to console", fn = UI.report }

    if SandboxVars and SandboxVars.KnoxLifeOverkill then
        local on = runtimeGet("KnoxLifeOverkill", "Debug", false) and true or false
        local function overkillLabel()
            local v = runtimeGet("KnoxLifeOverkill", "Debug", false)
            return "Overkill: log every kill  [" .. (v and "ON" or "OFF") .. "]"
        end
        rows[#rows + 1] = {
            label = overkillLabel(),
            -- Relabel the button in place. Reopening the whole panel from inside
            -- one of its own buttons' callbacks tears down the widget that is
            -- mid-click, which is the kind of thing that works until it does not.
            relabel = overkillLabel,
            fn = function()
                local now = not (runtimeGet("KnoxLifeOverkill", "Debug", false) and true or false)
                runtimeSet("KnoxLifeOverkill", "Debug", now)
                say("Overkill kill logging " .. (now and "ON" or "OFF"))
            end }
    end

    return rows
end

function UI:createChildren()
    ISPanel.createChildren(self)
    local rows = UI.rows()

    local w = 0
    for _, r in ipairs(rows) do
        w = math.max(w, getTextManager():MeasureStringX(UIFont.Small, r.label) + PAD * 4)
    end
    w = math.max(w, 280)
    self:setWidth(w)

    local y = PAD + FONT_HGT + PAD
    for _, r in ipairs(rows) do
        local b
        b = ISButton:new(PAD, y, w - PAD * 2, ROW, r.label, self,
            function()
                if r.fn then r.fn() end
                if r.relabel and b.setTitle then b:setTitle(r.relabel()) end
            end)
        b:initialise()
        b:instantiate()
        if not r.fn then b:setEnable(false) end
        self:addChild(b)
        y = y + ROW + 4
    end

    local close = ISButton:new(PAD, y + 4, w - PAD * 2, ROW, "Close", self,
        function() self:removeFromUIManager(); UI.instance = nil end)
    close:initialise()
    close:instantiate()
    if close.enableCancelColor then close:enableCancelColor() end
    self:addChild(close)

    self:setHeight(y + ROW + PAD + 4)
end

function UI:render()
    ISPanel.render(self)
    self:drawTextCentre("KnoxLife", self.width / 2, PAD,
        1, 1, 1, 1, UIFont.Medium)
end

function UI.OnOpenPanel()
    -- Rebuilt rather than reused: route counts, the installed add-on set and
    -- the Overkill toggle label all change between openings.
    if UI.instance then
        UI.instance:removeFromUIManager()
        UI.instance = nil
    end
    local ui = UI:new(120, 120, 300, 100)
    ui.moveWithMouse = true
    ui:initialise()
    ui:instantiate()
    ui:addToUIManager()
    UI.instance = ui
    return ui
end

-- Wrap rather than replace, so every vanilla button and any other mod's button
-- survives. Guarded because Lua is reloaded on some transitions and a second
-- wrap would add the entry twice.
if not ISDebugMenu.KnoxLifePatched then
    ISDebugMenu.KnoxLifePatched = true
    local original = ISDebugMenu.setupButtons
    function ISDebugMenu:setupButtons()
        original(self)
        local info = { title = "KnoxLife", func = function() UI.OnOpenPanel() end,
                       tab = "MAIN", marginTop = 0 }
        -- setupButtons sorts alphabetically and THEN appends the Close buttons,
        -- so a plain insert lands underneath Close. Step back over the trailing
        -- Close entries and sit just above them.
        local at = #self.buttons + 1
        local closeText = getText("IGUI_DebugMenu_Close")
        for i = #self.buttons, 1, -1 do
            if self.buttons[i].title == closeText then at = i else break end
        end
        table.insert(self.buttons, at, info)
        return info
    end
end
