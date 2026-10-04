--!strict
local GiftTier = {}
function GiftTier.forCoins(coins: number): number
	if coins >= 10000 then return 5 end
	if coins >= 1000 then return 4 end
	if coins >= 100 then return 3 end
	if coins >= 10 then return 2 end
	return 1
end
return GiftTier
