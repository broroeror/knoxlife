package com.knoxlife.zb;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.action.ActionGroup;

/**
 * Merge mod-supplied action states after the engine has loaded its own.
 *
 * warmUp = true because ActionGroup is loaded early by the animation system and
 * the patch has to be in place before the first getActionGroup call, which is
 * during game start.
 */
@Patch(className = "zombie.characters.action.ActionGroup",
       methodName = "getActionGroup",
       warmUp = true)
public class ActionGroupPatch {

    @Patch.OnExit
    public static void exit(@Patch.Argument(0) String name,
                            @Patch.Return ActionGroup group) {
        ModActionGroups.merge(name, group);
    }
}
