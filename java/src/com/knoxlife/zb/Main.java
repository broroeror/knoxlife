package com.knoxlife.zb;

import se.krka.kahlua.integration.annotations.LuaMethod;

/**
 * The KnoxLife ZombieBuddy plugin.
 *
 * WHAT THIS IS, AND WHERE IT LIVES
 *
 * ZombieBuddy loads a jar declared by any mod in that mod's own mod.info
 * (javaJarFile + javaPkgName), so this ships INSIDE KnoxLife core rather than
 * as a separate Workshop item. When ZombieBuddy is absent the jar is never
 * loaded: it is inert bytes on disk, which is what makes shipping it free.
 * See ADDON.md for why that shape was chosen over a separate addon.
 *
 * ⚠️ THE CORE MUST STAY PLAYABLE WITHOUT THIS. Every feature flag in
 * KW_JavaBridge starts false and every caller has to work with all of them
 * false. This file's job is to turn on only what it has actually verified.
 *
 * ⚠️ AND IT MUST FAIL CLOSED. "ZombieBuddy is running" is NOT evidence that a
 * patch worked -- KW_AnimSets says so explicitly. A flag is flipped only after
 * the thing it advertises is in place, never on load.
 */
public class Main {

    /** Set once main() has run, so Lua can tell "loaded" from "installed". */
    private static boolean loaded = false;

    public static void main(String[] args) {
        loaded = true;
        System.out.println("[KnoxLife] Java layer loaded (ZombieBuddy plugin)");
    }

    /**
     * Lua asks this. Its presence alone proves the whole chain: mod.info
     * declared the jar, ZombieBuddy found and loaded it, the package name
     * matched, and the Lua exposure worked. That is four things that can each
     * fail silently, which is why the first build does nothing else.
     */
    @LuaMethod(name = "KnoxLifeJavaLoaded", global = true)
    public static boolean isLoaded() {
        return loaded;
    }

    /**
     * Which capabilities this build actually provides, as a comma list for
     * KW_JavaBridge to parse.
     *
     * ⚠️ REPORTS WHAT HAS HAPPENED, NOT WHAT IS COMPILED IN. `ownAnimSets`
     * appears only once a mod action state has actually been merged, because
     * "the patch class is in the jar" is not evidence it applied -- the class
     * could fail to match, the method could be renamed by a game update, or the
     * walk could find nothing. This is the same fail-closed rule KW_AnimSets
     * states for the Lua side, applied at the source.
     */
    @LuaMethod(name = "KnoxLifeJavaCapabilities", global = true)
    public static String capabilities() {
        StringBuilder sb = new StringBuilder();
        if (ModActionGroups.merges() > 0) sb.append("ownAnimSets");
        return sb.toString();
    }

    /**
     * Ask the engine for every mod-supplied action group, exercising the patch.
     * Lua calls this at OnGameBoot; see ModActionGroups.warmModGroups for why
     * it is not done in main().
     */
    @LuaMethod(name = "KnoxLifeWarmActionGroups", global = true)
    public static int warmActionGroups() {
        return ModActionGroups.warmModGroups();
    }

    /** Diagnostics, so a person can see what the patch did without guessing. */
    @LuaMethod(name = "KnoxLifeActionGroupMerges", global = true)
    public static int actionGroupMerges() {
        return ModActionGroups.merges();
    }

    @LuaMethod(name = "KnoxLifeJavaLastError", global = true)
    public static String lastError() {
        return ModActionGroups.lastError();
    }
}
