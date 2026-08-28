package com.knoxlife.zb;

import zombie.characters.action.ActionGroup;
import zombie.characters.animals.AnimalDefinitions;

/**
 * Point an animal stage at OUR action group instead of its vanilla fallback.
 *
 * `AnimalDefinitions.animset` is a plain public String and `getAnimalDefs()` is
 * a public static map, so no new engine API is needed -- the whole difficulty
 * is doing it only when it is safe. ADDON.md records the consequence of getting
 * that wrong: "a refused flip is an animal that animates exactly as it does
 * today. An unchecked flip is the main menu."
 *
 * ⚠️ VERIFY POSITIVELY, DO NOT INFER. "ZombieBuddy is running" proves nothing,
 * and neither does "our jar loaded" -- the patch can be live and still have
 * merged nothing if a game update moved the method or the walk found no files.
 * So this asks the engine for the group and checks it came back carrying the
 * states we shipped, which is the only claim that cannot be true by accident.
 */
public final class AnimSets {

    private AnimSets() {}

    /** States every KnoxLife group ships. A group holding these is really ours. */
    private static final String[] REQUIRED = { "idle", "walk" };

    private static volatile int applied = 0;
    private static volatile String lastRefusal = "";

    public static int applied() { return applied; }
    public static String lastRefusal() { return lastRefusal; }

    /**
     * ⚠️ TRAP 2 FROM ADDON.md. getActionGroup CACHES a group before it loads
     * it, and returns a non-null EMPTY group on failure -- so anything that
     * asked for `kwc_fox` before our patch was live has poisoned the cache
     * permanently, and a perfectly good patch afterwards changes nothing.
     * reloadAll() is public, static, and re-runs load() on every cached group,
     * which repairs exactly that.
     */
    public static int reloadAll() {
        try {
            ActionGroup.reloadAll();
            return 1;
        } catch (Throwable t) {
            lastRefusal = "reloadAll: " + t;
            return 0;
        }
    }

    /**
     * Flip one stage, or refuse and say why. Returns true only if the engine
     * definition now names our group.
     */
    public static boolean apply(String stage, String animset) {
        try {
            if (stage == null || animset == null) {
                lastRefusal = "null argument"; return false;
            }
            ActionGroup g = ActionGroup.getActionGroup(animset);
            if (g == null) {
                lastRefusal = animset + ": no such action group"; return false;
            }
            for (String need : REQUIRED) {
                if (g.findState(need) == null) {
                    // An empty group here is trap 1: cached before the patch.
                    lastRefusal = animset + ": group has no '" + need
                                + "' state, so our states did not load";
                    return false;
                }
            }
            AnimalDefinitions def = AnimalDefinitions.getAnimalDefs().get(stage);
            if (def == null) {
                lastRefusal = stage + ": no such animal definition"; return false;
            }
            def.animset = animset;
            applied++;
            System.out.println("[KnoxLife] animset: " + stage + " -> " + animset);
            return true;
        } catch (Throwable t) {
            // Never throw at a Lua boundary either; a refusal is recoverable,
            // an exception mid-definition-load is not.
            lastRefusal = String.valueOf(t);
            return false;
        }
    }
}
