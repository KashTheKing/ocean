-- Boots the ocean on this side. The Studio plugin carries a copy of this module too, and in a
-- playtest that copy lives under PluginDebugService, where RunContext scripts also run: never boot it.
local top: Instance = script
while top.Parent and top.Parent ~= game do
	top = top.Parent
end
if top.ClassName ~= "PluginDebugService" then
	require(script.Parent).Init()
end
