--- The half-installed-ZombieBuddy notice, on the main menu.
---
--- WHY IT MOVED HERE
---
--- It used to be HaloTextHelper over the player's head at spawn. That is about
--- one second on screen, during the busiest moment in the game, and it competed
--- with every other mod doing the same thing. Nobody read it. A message nobody
--- reads is worse than no message, because it lets us believe we warned them.
---
--- The main menu is the opposite: nothing else is happening, the player is
--- already reading, and -- this is the part that matters -- the fix is a LAUNCH
--- OPTION, which can only be applied from outside the game anyway. Telling
--- someone mid-run to restart with a different command line is telling them at
--- the one moment they cannot act on it.
---
--- WHAT IT MUST NOT DO
---
--- Hold anyone up. It is not modal, it takes no focus, it never blocks a click
--- on Play, and it closes for good the moment it is dismissed. Someone who does
--- not want the Java layer should be able to ignore this forever at no cost --
--- the core mod is complete without it, and a nag would be a lie about that.
---
--- ⚠️ THE LAUNCH OPTION IS ORDER-SENSITIVE, and this is the whole reason the
--- upstream install guide says to copy the jar into the game folder instead.
--- `ProjectZomboid64` splits Steam's launch options on a bare `--`: everything
--- BEFORE it becomes a JVM argument, everything after goes to the game. The
--- launcher's own logging says so -- it prints `vmArg (json)` for the ones in
--- ProjectZomboid64.json and `vmArg (args)` for the ones it took from the
--- command line. A `-javaagent:` pasted after the `--` is handed to the game as
--- a plain argument, the JVM never sees it, the agent never starts, and nothing
--- reports an error. So we show the option AND say where it goes.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

require "KnoxLife/KW_JavaBridge"

local ZB = "ZombieBuddy"

--- Absolute path to the agent jar, or nil if it cannot be worked out.
---
--- Derived rather than hardcoded, because the answer differs per machine and per
--- install route: a Workshop subscription puts it under steamapps/workshop, a
--- manual install puts it wherever the player put it, and the separator differs
--- on Windows. `getModInfoByID(id):getDir()` is the mod's own directory in every
--- case, which is what makes an exact path possible instead of a placeholder
--- the player has to translate.
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
-- ---------------------------------------------------------------------------

local PAD    = 12
local NOTICE = ISPanel:derive("KWJavaNotice")

function NOTICE:createChildren()
    local bh = 22
    local bw = 118
    self.copyBtn = ISButton:new(self.width - PAD - bw * 2 - 6,
                                self.height - PAD - bh, bw, bh,
                                "Copy option", self, NOTICE.onCopy)
    self.copyBtn:initialise(); self.copyBtn:instantiate()
    self.copyBtn.borderColor = { r = 0.5, g = 0.5, b = 0.5, a = 0.6 }
    self:addChild(self.copyBtn)

    self.closeBtn = ISButton:new(self.width - PAD - bw,
                                 self.height - PAD - bh, bw, bh,
                                 "Dismiss", self, NOTICE.onClose)
    self.closeBtn:initialise(); self.closeBtn:instantiate()
    self.closeBtn.borderColor = { r = 0.5, g = 0.5, b = 0.5, a = 0.6 }
    self:addChild(self.closeBtn)

    -- No jar path means nothing to copy. Leaving an enabled button that does
    -- nothing is how a UI teaches people to distrust it.
    if not self.option then self.copyBtn:setEnable(false) end
end

function NOTICE:onCopy()
    if not self.option then return end
    pcall(function() Clipboard.setClipboard(self.option) end)
    self.copyBtn:setTitle("Copied")
end

function NOTICE:onClose()
    self:removeFromUIManager()
end

function NOTICE:render()
    ISPanel.render(self)
    local x, y = PAD, PAD
    self:drawText("KnoxLife", x, y, 0.85, 0.78, 0.55, 1, UIFont.Medium)
    y = y + 20
    self:drawText("ZombieBuddy is installed but not running, so the optional",
                  x, y, 0.82, 0.82, 0.82, 1, UIFont.Small); y = y + 15
    self:drawText("animation features are off. Everything else works normally.",
                  x, y, 0.82, 0.82, 0.82, 1, UIFont.Small); y = y + 20

    if self.option then
        self:drawText("Add to Steam > Launch Options, BEFORE the --",
                      x, y, 0.75, 0.75, 0.75, 1, UIFont.Small); y = y + 15
        self:drawText(KW.ellipsizePath(self.option, 62),
                      x, y, 0.60, 0.85, 0.60, 1, UIFont.Small); y = y + 18
        self:drawText("The jar does NOT need copying into the game folder.",
                      x, y, 0.62, 0.62, 0.62, 1, UIFont.Small)
    else
        self:drawText("Add -javaagent:<path to ZombieBuddy.jar> to Steam >",
                      x, y, 0.75, 0.75, 0.75, 1, UIFont.Small); y = y + 15
        self:drawText("Launch Options, BEFORE the --.",
                      x, y, 0.75, 0.75, 0.75, 1, UIFont.Small)
    end
end

function NOTICE:new(x, y, w, h, option)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.option          = option
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.82 }
    o.borderColor     = { r = 0.45, g = 0.42, b = 0.30, a = 0.9 }
    o.moveWithMouse   = true
    return o
end

-- ---------------------------------------------------------------------------

local shown = false

--- Did the main-menu notice actually appear this launch?
---
--- KW_JavaBridge asks before falling back to an in-game message. The main menu
--- is the right place to say this, but a mod's Lua running at the main menu is
--- not something we can prove for every future build -- the mods that do it
--- today hook OnMainMenuEnter AND a second event for exactly that reason. So
--- rather than trust it, the in-game path stays as a fallback and this is how it
--- knows to stay quiet.
function KW.javaNoticeShown() return shown end

function KW.showJavaNotice()
    if shown then return false end
    -- Only the half-installed case talks. "absent" is somebody who never asked
    -- for the Java layer, and "active" already works. See KW_JavaBridge.
    if KW.javaState() ~= "dormant" then return false end
    shown = true

    local w, h = 430, 150
    local sw, sh = 1024, 768
    pcall(function()
        sw = getCore():getScreenWidth()
        sh = getCore():getScreenHeight()
    end)
    -- Bottom right, inset. Away from the menu buttons on the left and the
    -- version string along the bottom edge.
    local p = NOTICE:new(sw - w - 24, sh - h - 48, w, h, KW.javaLaunchOption())
    p:initialise()
    p:addToUIManager()
    return true
end

if Events and Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Add(function() pcall(KW.showJavaNotice) end)
end
