package com.knoxlife.zb;

import zombie.ZomboidFileSystem;
import zombie.characters.action.ActionGroup;
import zombie.characters.action.ActionState;

import java.io.File;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Let an action group pick up states from MOD directories, not just the game's.
 *
 * THE ENGINE LIMITATION THIS EXISTS FOR
 *
 * ActionGroup.load() resolves its directory through
 * ZomboidFileSystem.getMediaFile(), which is `new File(workdir, path)` -- the
 * GAME directory and nothing else. Verified from bytecode: load() calls
 * getMediaFile twice, once for the group file and once for the directory it
 * lists for states. AnimationSet by contrast has walkGameAndModFiles available,
 * which searches game AND mods. So a mod can ship an animset and cannot ship
 * the action group that drives it, and that asymmetry is the single thing
 * blocking our own animal animations (ADDON.md, STATUS 7h).
 *
 * ⚠️ WHY PATCH getActionGroup AND NOT load(). load() is private and an
 * instance method, and ZombieBuddy's Patch API has no `this` binding -- it
 * offers Argument, AllArguments, Return, Local, SuperCall, SuperMethod, and
 * nothing for the receiver. getActionGroup(String) is static and RETURNS the
 * group, and getOrCreate/ActionState.load are both public, so the merge can be
 * done from outside. It also runs at exactly the right moment: ADDON.md records
 * that getActionGroup caches the group BEFORE loading it, so by the time it
 * returns, vanilla's own states are already in.
 */
public final class ModActionGroups {

    /** Groups already merged. getActionGroup is called constantly. */
    private static final Set<String> done = ConcurrentHashMap.newKeySet();

    private static volatile int merges = 0;
    private static volatile String lastError = "";

    private ModActionGroups() {}

    public static int merges() { return merges; }
    public static String lastError() { return lastError; }

    static void merge(String name, ActionGroup group) {
        if (name == null || group == null) return;
        if (!done.add(name)) return;
        try {
            // The game's own copy, so it can be skipped: vanilla load() has
            // already read it, and calling ActionState.load twice on the same
            // directory appends its transitions a second time.
            String rel = "actiongroups/" + name;
            File gameDir = ZomboidFileSystem.instance.getMediaFile(rel);
            String gamePath = gameDir == null ? "" : gameDir.getAbsolutePath();

            ZomboidFileSystem.instance.walkGameAndModFiles(rel, false, (file, relPath) -> {
                try {
                    if (file == null || !file.isDirectory()) return;
                    if (file.getAbsolutePath().startsWith(gamePath)) return;   // vanilla's

                    // The walker may hand back the GROUP directory or the state
                    // directories inside it depending on how it recurses, so
                    // handle both rather than assume. A state directory is one
                    // whose parent is the group.
                    if (file.getName().equals(name)) {
                        File[] kids = file.listFiles();
                        if (kids == null) return;
                        for (File kid : kids) addState(group, kid);
                    } else {
                        addState(group, file);
                    }
                } catch (Throwable t) {
                    lastError = String.valueOf(t);
                }
            });
        } catch (Throwable t) {
            // ⚠️ NEVER throw out of a patch. An exception here lands inside the
            // engine's own call and takes the animation system down with it,
            // which is far worse than an animal that walks the vanilla way.
            lastError = String.valueOf(t);
        }
    }

    /**
     * Ask the engine for every action group a MOD ships, which both proves the
     * patch works and pre-warms the groups.
     *
     * ⚠️ THIS BREAKS A DEADLOCK. Our patch only runs when something calls
     * getActionGroup, and nothing calls it for `kwc_fox` because KW_AnimSets
     * ships dormant and no definition names an animset -- and it stays dormant
     * until the Java layer reports `ownAnimSets`, which this class only reports
     * once it has actually merged something. Each side was waiting for the
     * other. Requesting the groups ourselves settles it with evidence rather
     * than by assuming: if the merge works, the capability is earned.
     *
     * Called from Lua at OnGameBoot rather than from main(), because main()
     * runs during mod loading and ZomboidFileSystem's mod list is not something
     * this code should assume is populated that early.
     */
    public static int warmModGroups() {
        try {
            File gameRoot = ZomboidFileSystem.instance.getMediaFile("actiongroups");
            String gamePath = gameRoot == null ? "" : gameRoot.getAbsolutePath();
            Set<String> names = ConcurrentHashMap.newKeySet();
            ZomboidFileSystem.instance.walkGameAndModFiles("actiongroups", false, (file, rel) -> {
                if (file == null || !file.isDirectory()) return;
                if (file.getAbsolutePath().startsWith(gamePath)) return;
                File[] kids = file.getName().equals("actiongroups")
                              ? file.listFiles() : new File[] { file };
                if (kids == null) return;
                for (File k : kids) {
                    if (k != null && k.isDirectory()) names.add(k.getName());
                }
            });
            for (String n : names) {
                // Going through getActionGroup, not merge() directly, so the
                // patch itself is what gets exercised. If the patch did not
                // apply, merges stays 0 and nothing is claimed.
                ActionGroup.getActionGroup(n);
            }
            System.out.println("[KnoxLife] warmed " + names.size()
                               + " mod action group(s): " + names);
            return names.size();
        } catch (Throwable t) {
            lastError = String.valueOf(t);
            return 0;
        }
    }

    private static void addState(ActionGroup group, File dir) {
        if (dir == null || !dir.isDirectory()) return;
        ActionState st = group.getOrCreate(dir.getName());
        if (st == null) return;
        st.load(dir.getPath());
        merges++;
        System.out.println("[KnoxLife] action group '" + group.getName()
                           + "': merged mod state '" + dir.getName() + "'");
    }
}
