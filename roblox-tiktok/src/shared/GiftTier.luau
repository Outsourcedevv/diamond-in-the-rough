--!strict
local GiftTier = {}
function GiftTier.forCoins(coins: number): number
	if coins >= 10000 then return 6 end
	if coins >= 1000 then return 5 end
	if coins >= 500 then return 4 end
	if coins >= 100 then return 3 end
	if coins >= 10 then return 2 end
	return 1
end
-- The show to play: the one chosen for the gift in the gift settings (1 to 6),
-- otherwise the one its coins pick.
function GiftTier.pick(coins: number, chosen: any): number
	if type(chosen) == "number" and chosen == math.floor(chosen) and chosen >= 1 and chosen <= 6 then return chosen end
	return GiftTier.forCoins(coins)
end
return GiftTier
