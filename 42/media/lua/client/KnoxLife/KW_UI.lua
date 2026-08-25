-- Knox Life -- the few UI facts the admin panels must agree on.
--
-- WHY MEASURING IS NOT OPTIONAL
--
-- The planner shipped with its columns at hardcoded pixel offsets -- name 0,
-- density 210, group 290 -- which is only ever correct at the one UI scale the
-- author happened to be running. On a 4K display at a larger scale the header
-- rendered as "per sq mgroup": the strings had outgrown the gaps, and every
-- number sat under the label of the column to its right. Nothing was wrong with
-- the data and the panel looked broken.
--
-- So: never place a column at a constant. Measure the widest cell that will go
-- in it and lay the table out from that. Everything here exists to make doing
-- that the short path.
--
-- WHY THE BACKGROUND IS OPAQUE
--
-- ISPanel defaults to a=0.5 (ISPanel.lua:105). Over grass or a lit road that
-- leaves dim text on a bright, moving background and the panel becomes unusable
-- exactly when someone is standing outdoors looking at wildlife, which is the
-- whole audience. These panels are read, not admired through.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

KW.UI = KW.UI or {}
local U = KW.UI

U.BG      = { r = 0.055, g = 0.065, b = 0.055, a = 0.97 }
U.BORDER  = { r = 0.42,  g = 0.45,  b = 0.38,  a = 1.00 }
U.HEADBG  = { r = 0.10,  g = 0.12,  b = 0.10,  a = 1.00 }
U.RULE    = { 1, 1, 1, 0.22 }               -- a, r, g, b for drawRect
U.TEXT    = { 0.92, 0.93, 0.89 }
U.DIM     = { 0.66, 0.68, 0.62 }
U.WARN    = { 0.96, 0.74, 0.34 }
U.PAD     = 14

--- Width of a string in a font, in pixels, right now.
function U.w(font, s)
    return getTextManager():MeasureStringX(font, tostring(s or ""))
end

--- Height of a font, in pixels, right now.
--
-- Deliberately a function and not a constant captured at file scope. Font
-- metrics depend on the UI scale, which the player can change without
-- restarting, and a cached height silently mislays every row below it.
function U.h(font)
    return getTextManager():getFontHeight(font)
end

--- Widest of a list of strings, for sizing a column to its contents.
function U.widest(font, list)
    local m = 0
    for _, s in ipairs(list) do
        local n = U.w(font, s)
        if n > m then m = n end
    end
    return m
end

--- Give a panel the house skin: opaque, bordered, readable over anything.
function U.skin(panel)
    panel.backgroundColor = { r = U.BG.r, g = U.BG.g, b = U.BG.b, a = U.BG.a }
    panel.borderColor     = { r = U.BORDER.r, g = U.BORDER.g, b = U.BORDER.b, a = U.BORDER.a }
    return panel
end

--- A filled swatch with a dark seat, so a pale colour still reads on the panel.
function U.swatch(panel, x, y, size, r, g, b)
    panel:drawRect(x - 1, y - 1, size + 2, size + 2, 0.85, 0, 0, 0)
    panel:drawRect(x, y, size, size, 1.0, r, g, b)
end

return U
