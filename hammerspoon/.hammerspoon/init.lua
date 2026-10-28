-- Cmd+G checks the selection (or clipboard) in the writing HUD.
require("hs.ipc")
grammarChecker = require("grammar_checker").setup()

-- Caps Lock + T arrives as F19 from the existing Karabiner layer.
correctTitleCase = require("correct_title_case")
aerospaceSwitcher = require("aerospace_switcher")

local previousShutdown = hs.shutdownCallback
hs.shutdownCallback = function()
    grammarChecker.shutdown()
    if previousShutdown then previousShutdown() end
end

hs.alert.show("Hammerspoon config loaded ✓")
