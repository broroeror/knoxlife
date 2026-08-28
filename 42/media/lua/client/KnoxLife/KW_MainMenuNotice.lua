--- The half-installed-ZombieBuddy notice: once on the main menu, once in game.
---
--- WHY IT IS NOT HALO TEXT
---
--- It used to be HaloTextHelper over the player's head at spawn. That is about
--- one second on screen, during the busiest moment in the game, competing with
--- every other mod doing the same thing. Nobody read it. A message nobody reads
--- is worse than none, because it lets us believe we warned them.
---
--- WHY IT FIRES TWICE
---
--- The fix is a LAUNCH OPTION, so the main menu is the only place a player can
--- act on it -- and on a server it is the only place they will ever see it at
--- all, because a client that cannot join never reaches OnCreatePlayer.
---
--- But the main menu alone is not reliable, for a reason worth writing down:
--- ⚠️ OUR LUA IS NOT LOADED WHEN THE MAIN MENU FIRST APPEARS. Mod Lua loads
--- when the mod list is loaded, so on a cold launch OnMainMenuEnter has already
--- fired before this file exists. Observed in play: the notice appeared only
--- after opening the Mods screen and enabling KnoxLife, which reloads Lua in
--- place. Hence OnFETick below, and hence the in-game showing as well -- in game
--- we are unambiguously loaded.
---
--- WHAT IT MUST NOT DO
---
--- Hold anyone up. Not modal, takes no focus, never blocks Play, closes for good
--- when dismissed, and shows at most once per context. Someone who does not want
--- the Java layer can ignore it at no cost -- the core is complete without it,
--- and a nag would be a lie about that.
---
--- ⚠️ THE LAUNCH OPTION IS ORDER-SENSITIVE, and that is probably why the
--- upstream guide says to copy the jar into the game folder instead.
--- `ProjectZomboid64` splits Steam's launch options on a bare `--`: everything
--- BEFORE it becomes a JVM argument, everything after goes to the game. The
--- launcher's own logging says so -- `vmArg (json)` for the ones in
--- ProjectZomboid64.json, `vmArg (args)` for the ones taken from the command
--- line. A `-javaagent:` after the `--` is passed to the game as a plain
--- argument: the JVM never sees it, the agent never starts, and nothing reports
--- an error. So we show the option AND say where it goes.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

require "KnoxLife/KW_JavaBridge"

local ZB = "ZombieBuddy"

--- Absolute path to the agent jar, or nil if it cannot be worked out.
---
--- Derived rather than hardcoded: the answer differs per machine and per install
--- route -- a Workshop subscription puts it under steamapps/workshop, a manual
--- install wherever the player put it, and the separator differs on Windows.
--- `getModInfoByID(id):getDir()` is the mod's own directory in every case, which
--- is what makes an exact path possible instead of a placeholder to translate.
function KW.zombieBuddyJar()
    local dir
    pcall(function()
        local info = getModInfoByID and getModInfoByID(ZB)
        if info and info.getDir then dir = info:getDir() end
    end)
    if not dir or dir == "" then return nil end
    dir = tostring(dir):gsub("[/\\]+$", "")
    local sep = dir:find("\\") and "\\" or "/"
    return dir .. sep .. "libs" .. sep .. ZB .. ".jar"
end

--- The exact thing to paste, or nil if we could not locate the jar.
function KW.javaLaunchOption()
    local jar = KW.zombieBuddyJar()
    if not jar then return nil end
    return "-javaagent:" .. jar
end

--- Shorten the middle of a path so a long one still shows both ends.
--- The clipboard always gets the whole thing; this is only what is drawn.
function KW.ellipsizePath(s, maxChars)
    s = tostring(s or "")
    maxChars = maxChars or 58
    if #s <= maxChars then return s end
    local keep = math.floor((maxChars - 3) / 2)
    return s:sub(1, keep) .. "..." .. s:sub(#s - keep + 1)
end

-- ---------------------------------------------------------------------------
-- The panel
--
-- ⚠️ EVERY SIZE HERE IS MEASURED, NEVER GUESSED. The first version hardcoded
-- 430x150 with a 15px line step and every single line overran the edge, the
-- buttons sat on top of the text, and the rows overlapped each other. Font
-- height and string width depend on the font, the UI scale and the player's
-- resolution, none of which are knowable when writing the file.
-- ---------------------------------------------------------------------------

local PAD  = 14
local GAP  = 6            -- between the text block and the buttons
local MAXW = 660          -- ceiling, so a long path elides instead of spanning

local NOTICE = ISPanel:derive("KWJavaNotice")

local function tm() return getTextManager() end
local function widthOf(font, s)
    local w = 0
    pcall(function() w = tm():MeasureStringX(font, s) end)
    return w
end
local function heightOf(font)
    local h = 0
    pcall(function() h = tm():getFontHeight(font) end)
    if h <= 0 then h = 16 end
    return h
end

--- Trim a path until it actually fits `maxpx`, by binary search on the character
--- budget. Measuring is the only way to know: "62 characters" was a guess and it
--- overran by roughly a third of the box.
local function fitToWidth(s, font, maxpx)
    if widthOf(font, s) <= maxpx then return s end
    local lo, hi = 8, #s
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if widthOf(font, KW.ellipsizePath(s, mid)) <= maxpx then lo = mid
        else hi = mid - 1 end
    end
    return KW.ellipsizePath(s, lo)
end

--- The lines to draw, before fitting. Colour is per line because the path is the
--- one thing the player has to act on and should read as such.
local function buildLines(option)
    local L = {
        { t = "KnoxLife", f = UIFont.Medium, c = { 0.85, 0.78, 0.55 } },
        { t = "ZombieBuddy is installed but not running, so the optional",
          f = UIFont.Small, c = { 0.82, 0.82, 0.82 } },
        { t = "animation features are off. Everything else works normally.",
          f = UIFont.Small, c = { 0.82, 0.82, 0.82 } },
    }
    if option then
        L[#L + 1] = { t = "Add to Steam > Launch Options, BEFORE the  --",
                      f = UIFont.Small, c = { 0.75, 0.75, 0.75 } }
        L[#L + 1] = { t = option, f = UIFont.Small, c = { 0.55, 0.85, 0.55 },
                      path = true }
    else
        L[#L + 1] = { t = "Add  -javaagent:<path to ZombieBuddy.jar>  to Steam >",
                      f = UIFont.Small, c = { 0.75, 0.75, 0.75 } }
        L[#L + 1] = { t = "Launch Options, BEFORE the  --", f = UIFont.Small,
                      c = { 0.75, 0.75, 0.75 } }
    end
    L[#L + 1] = { t = "The jar does NOT need copying into the game folder.",
                  f = UIFont.Small, c = { 0.62, 0.62, 0.62 } }
    return L
end

function NOTICE:createChildren()
    local bh = math.max(22, heightOf(UIFont.Small) + 8)
    local bw = math.max(96, widthOf(UIFont.Small, "Copy option") + 22)
    local y  = self.height - PAD - bh
    self.copyBtn = ISButton:new(self.width - PAD - bw * 2 - GAP, y, bw, bh,
                                "Copy option", self, NOTICE.onCopy)
    self.copyBtn:initialise(); self.copyBtn:instantiate()
    self:addChild(self.copyBtn)

    self.closeBtn = ISButton:new(self.width - PAD - bw, y, bw, bh,
                                 "Dismiss", self, NOTICE.onClose)
    self.closeBtn:initialise(); self.closeBtn:instantiate()
    self:addChild(self.closeBtn)

    -- Nothing to copy means the button must not pretend otherwise. An enabled
    -- control that does nothing is how a UI teaches people to distrust it.
    if not self.option then self.copyBtn:setEnable(false) end
end

function NOTICE:onCopy()
    if not self.option then return end
    pcall(function() Clipboard.setClipboard(self.option) end)
    self.copyBtn:setTitle("Copied")
end

function NOTICE:onClose() self:removeFromUIManager() end

function NOTICE:render()
    ISPanel.render(self)
    local y = PAD
    for _, ln in ipairs(self.lines) do
        local c = ln.c
        self:drawText(ln.draw, PAD, y, c[1], c[2], c[3], 1, ln.f)
        y = y + ln.h
    end
end

--- Work out the box from the text, rather than the other way round.
---
--- Exposed so it can be asserted offline: the first version hardcoded 430x150
--- and every line overran the edge with the buttons sitting on top of the text.
--- Returns the size, and the lines with their fitted text and row heights.
function KW.javaNoticeLayout(option)
    local lines = buildLines(option)
    local textMax = MAXW - PAD * 2

    -- Fit first, then measure: a path is elided down to the ceiling, everything
    -- else sets the width honestly.
    local w = 0
    for _, ln in ipairs(lines) do
        ln.draw = ln.path and fitToWidth(ln.t, ln.f, textMax) or ln.t
        ln.h    = heightOf(ln.f) + 2
        w = math.max(w, widthOf(ln.f, ln.draw))
    end

    local bh = math.max(22, heightOf(UIFont.Small) + 8)
    local bw = math.max(96, widthOf(UIFont.Small, "Copy option") + 22)
    w = math.max(w, bw * 2 + GAP) + PAD * 2

    local h = PAD
    for _, ln in ipairs(lines) do h = h + ln.h end
    h = h + GAP + bh + PAD
    return w, h, lines
end

function NOTICE:new(option)
    local w, h, lines = KW.javaNoticeLayout(option)

    local sw, sh = 1024, 768
    pcall(function()
        sw = getCore():getScreenWidth()
        sh = getCore():getScreenHeight()
    end)
    -- Bottom right, inset. Clear of the menu buttons on the left and the version
    -- string along the bottom edge; clamped so it cannot land off-screen on a
    -- small window.
    local x = math.max(8, sw - w - 24)
    local y = math.max(8, sh - h - 48)

    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.option          = option
    o.lines           = lines
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.88 }
    o.borderColor     = { r = 0.45, g = 0.42, b = 0.30, a = 0.9 }
    o.moveWithMouse   = true
    return o
end

-- ---------------------------------------------------------------------------

local shownIn = { menu = false, game = false }

--- Has it been shown in this context yet? `nil` asks about either.
---
--- KW_JavaBridge consults this before falling back to halo text.
function KW.javaNoticeShown(where)
    if where then return shownIn[where] == true end
    return shownIn.menu or shownIn.game
end

--- Show it once for `where` ("menu" or "game"). Returns whether it opened.
function KW.showJavaNotice(where)
    where = (where == "game") and "game" or "menu"
    if shownIn[where] then return false end
    -- Only the half-installed case talks. "absent" is somebody who never asked
    -- for the Java layer; "active" already works. See KW_JavaBridge.
    if KW.javaState() ~= "dormant" then return false end
    shownIn[where] = true

    local p = NOTICE:new(KW.javaLaunchOption())
    p:initialise()
    p:addToUIManager()
    return true
end

if Events and Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Add(function() pcall(KW.showJavaNotice, "menu") end)
end

-- ⚠️ The reason this exists: mod Lua is loaded with the mod list, so on a cold
-- launch OnMainMenuEnter has ALREADY fired by the time this file runs, and it
-- will not fire again until the player navigates away and back. Enabling the mod
-- in the Mods screen reloads Lua in place, which is the case observed in play --
-- the notice only appeared after that. OnFETick is the front-end tick, so one
-- pass through it tells us we are sitting at the menu right now. One shot, then
-- it unhooks itself; a handler that runs every frame forever to do nothing is a
-- cost with no payer.
if Events and Events.OnFETick then
    local function firstFrontEndTick()
        pcall(function() Events.OnFETick.Remove(firstFrontEndTick) end)
        pcall(KW.showJavaNotice, "menu")
    end
    Events.OnFETick.Add(firstFrontEndTick)
end
