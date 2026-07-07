------------------------------------------------------------
-- CLEPLER
-- controls/controls_button.lua
--
-- Thin reusable button helper. Pass width/height only when you
-- need a sized button; omit them for a natural-width button.
-- Returns true on press.
------------------------------------------------------------

local ImGui = require('ImGui')

local Button = {}

function Button.Draw(label, width, height)
    if width and height then
        return ImGui.Button(label, width, height) and true or false
    end
    return ImGui.Button(label) and true or false
end

return Button
