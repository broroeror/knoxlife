--- Our own animation sets and action groups -- shipped, dormant, addon-switchable.
---
--- WHAT IS ON DISK AND WHY IT DOES NOTHING
---
--- Every species mod ships a complete pair:
---
---     42/media/AnimSets/<group>/       the animations, one directory per state
---     42/media/actiongroups/<group>/   the state machine that reaches them
---
--- Neither is read by the running game today, and that is not discipline on our
--- part -- it is the engine, verified in bytecode:
---
---   * `AnimationSet.GetAnimationSet` is LAZY. It is `setMap.get(name)`, and only
---     on a miss does it construct one and call `Load`. Nothing anywhere
---     enumerates `AnimSets/`. `LuaManager$GlobalObject.refreshAnimSets` loads
---     four hardcoded names -- player, player-vehicle, zombie, zombie-crawler --
---     and no others. A set nobody NAMES is never opened.
---
---   * `ActionGroup.load()` resolves through `ZomboidFileSystem.getMediaFile`,
---     which is one line: `new File(workdir, path)`. It cannot see a mod at all.
---     Our actiongroup half is unreachable BY CONSTRUCTION.
---
--- And nothing names them, because no definition file sets `animset`. Ours
--- inherit the donor's value through the wholesale table copy -- "raccoon" for
--- the canids and the bobcat, "mouse" for the squirrel -- so every animal today
--- runs on a base-game set with a base-game action group, exactly as it did
--- before this payload existed. `check_definitions.py` fails the build if any
--- definition file sets `animset` explicitly, which is what keeps that true.
---
--- ⛔ DO NOT "ENABLE" THIS FROM LUA. There is no way to, and trying crashed the
--- client twice. Half a pair -- and from a mod it is ALWAYS half, however
--- correct the other half is -- leaves the animal with no action state machine,
--- and the first thing to ask it for one (a hit reaction, from a swing or even a
--- shove) throws on a null `currentState` and drops the player to the main menu.
--- See STATUS 7h for the full disassembly.
---
--- HOW THE ADDON TURNS IT ON
---
--- `AnimalDefinitions.animset` is a plain public String field, and
--- `AnimalDefinitions.animalDefs` is a public static HashMap with a public
--- static `getAnimalDefs()`. So a Java addon needs no new engine API to make the
--- switch -- it assigns the field. What it DOES need is for `actiongroups/` to
--- become mod-aware, which is one patch to `ActionGroup.load()`: resolve through
--- `walkGameAndModFiles` the way `AnimationSet.Load` already does.
---
--- The addon's whole job is then:
---
---     1. patch ActionGroup.load to search mods
---     2. for each entry in KW.animsetPlan():  verify, then flip
---     3. KnoxLife.java.ownAnimSets = true
---
--- ⚠️ THREE TRAPS, ALL VERIFIED IN BYTECODE, ALL CHEAP TO AVOID
---
--- 1. `getActionGroup` CACHES BEFORE IT LOADS. The bytecode puts the new group
---    into `s_actionGroupMap` at offset 49 and calls `load()` at 61, and it
---    returns a non-null EMPTY group on failure rather than null. So if anything
---    asks for `kwc_fox` before the patch is live, a stateless group is cached
---    permanently and a perfectly good patch afterwards changes nothing. Patch
---    before the first animal spawns.
---
--- 2. `ActionGroup.reloadAll()` IS THE ESCAPE HATCH from trap 1 -- public,
---    static, and it re-runs `load()` on every cached group. Call it after
---    patching and a poisoned cache repairs itself.
---
--- 3. THE FLIP MUST BE FAIL-CLOSED. "ZombieBuddy is running" is NOT evidence the
---    patch worked -- ZombieBuddy without our addon patches nothing, and our
---    addon against a game update that moved `load()` patches nothing either.
---    Verify positively before assigning: ask for the group and check it came
---    back with the states we shipped. A refused flip is an animal that animates
---    exactly as it does today. An unchecked flip is the main menu.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

--- ⚠️ Per-key, never `KW.java = KW.java or {...}`. This file is `shared` and
--- KW_JavaBridge is `client`, so whichever loads first would otherwise create
--- the table and leave the other file's defaults unset -- the flags would exist
--- as nil rather than false, and `if not KW.java.x` would still read correctly
--- while `KW.javaMissing()` silently stopped listing them.
KW.java = KW.java or {}
if KW.java.ownAnimSets == nil then KW.java.ownAnimSets = false end

--- group id -> spec. Filled by each species mod; the core hardcodes no species.
KW.animsets = KW.animsets or {}

--- Declare the animset pair a species mod ships.
---
---     KW.registerAnimSet("kwc_fox", {
---         animset  = "kwc_fox",     -- directory name under BOTH halves
---         fallback = "raccoon",     -- what its animals use while dormant
---         stages   = { "kwc_foxkit", "kwc_foxvixen", "kwc_foxdog" },
---         attack   = true,          -- the pair adds an attack state
---     })
---
--- Returns true when registered. Rejects anything it cannot act on later, on
--- the same principle as registerSpecies: a half-formed entry here becomes an
--- animset flip onto a group that does not exist, which is the crash.
function KW.registerAnimSet(groupId, spec)
    if type(groupId) ~= "string" or groupId == "" then
        KW.log("registerAnimSet: groupId must be a non-empty string")
        return false
    end
    if type(spec) ~= "table" then
        KW.log("registerAnimSet('" .. groupId .. "'): spec must be a table")
        return false
    end
    if type(spec.animset) ~= "string" or spec.animset == "" then
        KW.log("registerAnimSet('" .. groupId .. "'): needs an animset name")
        return false
    end
    if type(spec.fallback) ~= "string" or spec.fallback == "" then
        -- Without this the addon cannot put the animal back, and "revert" is
        -- the only recovery a player has if a game update breaks the patch.
        KW.log("registerAnimSet('" .. groupId .. "'): needs a fallback animset "
            .. "-- the base-game set its animals use while dormant")
        return false
    end
    if type(spec.stages) ~= "table" or #spec.stages == 0 then
        KW.log("registerAnimSet('" .. groupId .. "'): needs a non-empty stages "
            .. "list -- animalDefs is keyed by STAGE id, not by group")
        return false
    end

    local stages = {}
    for _, s in ipairs(spec.stages) do
        if type(s) == "string" and s ~= "" then stages[#stages + 1] = s end
    end
    if #stages ~= #spec.stages then
        KW.log("registerAnimSet('" .. groupId .. "'): every stage must be a "
            .. "non-empty string")
        return false
    end

    KW.animsets[groupId] = {
        animset  = spec.animset,
        fallback = spec.fallback,
        stages   = stages,
        attack   = spec.attack == true,
    }
    return true
end

--- The flat list of flips an addon applies, sorted so two runs agree.
---
--- Each entry is what the addon needs and nothing more:
---     { stage = "kwc_foxvixen", from = "raccoon", to = "kwc_fox", attack = true }
---
--- `from` is what makes revert possible, and revert is not a nicety: a game
--- update that moves ActionGroup.load turns a working addon into a crashing one,
--- and the fix has to be available without a re-download.
function KW.animsetPlan()
    local groups = {}
    for id in pairs(KW.animsets) do groups[#groups + 1] = id end
    table.sort(groups)

    local plan = {}
    for _, id in ipairs(groups) do
        local spec = KW.animsets[id]
        for _, stage in ipairs(spec.stages) do
            plan[#plan + 1] = {
                stage  = stage,
                from   = spec.fallback,
                to     = spec.animset,
                attack = spec.attack,
            }
        end
    end
    return plan
end

--- Are our own sets live? False everywhere until an addon has verified and
--- flipped. Everything that could use an attack animation asks THIS, never
--- `javaState()` -- the agent running is not evidence our patch took.
function KW.animsetsActive()
    return KW.java.ownAnimSets == true
end

--- Which groups claim an attack state. Empty while dormant, by design: a caller
--- that asks "can this species strike?" must get "no" until it really can.
function KW.animsetsWithAttack()
    if not KW.animsetsActive() then return {} end
    local out = {}
    for id, spec in pairs(KW.animsets) do
        if spec.attack then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

return KW.animsets
