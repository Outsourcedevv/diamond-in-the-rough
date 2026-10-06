--!strict
-- Which of the valley's own trees and plants each map theme hides, so a theme
-- can change the land as well as add to it: the desert has no pine forest or
-- meadow flowers, and the haunted night keeps only its dark pines (its dead
-- trees stand in for the leafy birches and oaks). Used by the
-- server's Scenery (for the built-in and imported scenery) and the client's
-- SceneryView (for the Blender pack built on each player's computer).
local SceneryThemes = {}

-- Theme -> kinds of scenery it hides. A kind is the leading word of a
-- scenery piece's name: "Pine" covers Pine_A and Pine_Snow_B, "Conifer" and
-- "Birch" the built-in trees.
SceneryThemes.HIDDEN = {
	desert = { Pine = true, Birch = true, Oak = true, Bush = true, Flowers = true, Log = true, Stump = true, Conifer = true },
	haunted = { Flowers = true, Birch = true, Oak = true },
} :: { [string]: { [string]: boolean } }

-- The kind of a scenery piece from its name ("Pine_Snow_A" -> "Pine").
function SceneryThemes.kind(name: string): string
	return string.match(name, "^(%a+)") or name
end

-- True if `theme` hides the scenery piece called `name`.
function SceneryThemes.hides(theme: string?, name: string): boolean
	local hidden = SceneryThemes.HIDDEN[theme or "default"]
	return hidden ~= nil and hidden[SceneryThemes.kind(name)] == true
end

-- True if any theme hides the scenery piece called `name`.
function SceneryThemes.themed(name: string): boolean
	local kind = SceneryThemes.kind(name)
	for _, hidden in SceneryThemes.HIDDEN do
		if hidden[kind] then return true end
	end
	return false
end

return SceneryThemes
