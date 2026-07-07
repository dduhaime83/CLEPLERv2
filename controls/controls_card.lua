------------------------------------------------------------
-- CLEPLER
-- controls/controls_card.lua
--
-- Visual section grouping: a colored header label followed by
-- content, terminated by a separator. Deliberately shallow --
-- no BeginChild/EndChild layout container -- to stay simple
-- and Lua-5.1-safe.
--
--   controls_card.Begin("Watchlist")
--   ... draw card contents ...
--   controls_card.End()
------------------------------------------------------------

local ImGui = require('ImGui')

local Card = {}

-- Header tint (soft blue).
local HDR_R, HDR_G, HDR_B, HDR_A = 0.6, 0.8, 1.0, 1.0

function Card.Begin(title)
    if title then
        ImGui.TextColored(HDR_R, HDR_G, HDR_B, HDR_A, title)
    end
    ImGui.Separator()
end

function Card.End()
    ImGui.Separator()
end

return Card
