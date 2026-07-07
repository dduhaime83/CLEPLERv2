------------------------------------------------------------
-- CLEPLER
-- spells.lua
------------------------------------------------------------
local mq=require('mq')
local Spells={}
Spells.Database={}
function Spells.Refresh()
 Spells.Database={}
 for gem=1,12 do
  local s=mq.TLO.Me.Gem(gem)()
  if s then
   print(string.format("[CLEPLER] Gem %d: %s",gem,s))
  end
 end
end
function Spells.Get(name) return Spells.Database[name] end
function Spells.Ready() return true end
return Spells