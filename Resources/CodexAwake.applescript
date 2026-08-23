-- CodexAwake 2.0 AppleScript bridge.
-- These handlers use the app's validated URL commands and never expose chat text or secrets.

use framework "AppKit"

on openCodexAwakeURL(value)
    set targetURL to current application's NSURL's URLWithString:value
    current application's NSWorkspace's sharedWorkspace()'s openURL:targetURL
end openCodexAwakeURL

on protectionOn()
    my openCodexAwakeURL("codexawake://protection/on")
end protectionOn

on protectionOff()
    my openCodexAwakeURL("codexawake://protection/off")
end protectionOff

on toggleProtection()
    my openCodexAwakeURL("codexawake://protection/toggle")
end toggleProtection

on applyWorkProfile()
    my openCodexAwakeURL("codexawake://profile/work")
end applyWorkProfile

on applyNightTaskProfile()
    my openCodexAwakeURL("codexawake://profile/night-task")
end applyNightTaskProfile

on applyClosedLidProfile()
    my openCodexAwakeURL("codexawake://profile/closed-lid")
end applyClosedLidProfile

on applyPresentationProfile()
    my openCodexAwakeURL("codexawake://profile/presentation")
end applyPresentationProfile
