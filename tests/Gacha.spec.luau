-- Specs for shared/Gacha. Run in Studio via test.project.json (see tests/init.server.luau).
return function(t)
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local Gacha = require(Shared.Gacha)
	local Rarities = require(Shared.Config.Rarities)

	local N = 100000

	t.test("rarity distribution matches weights with no luck", function()
		local rng = Random.new(1234)
		local counts = {}
		local pity = 0
		for _ = 1, N do
			local id
			id, pity = Gacha.rollRarity(rng, 0, 0) -- pity pinned at 0 so it never kicks in
			counts[id] = (counts[id] or 0) + 1
		end
		local odds = Gacha.rarityOdds(0, 0)
		for _, o in odds do
			local observed = (counts[o.id] or 0) / N
			t.near(observed, o.chance, math.max(0.004, o.chance * 0.15), o.id)
		end
	end)

	t.test("luck raises every non-Common weight", function()
		local base = Gacha.rarityOdds(0, 0)
		local lucky = Gacha.rarityOdds(1, 0)
		t.expect(lucky[1].chance < base[1].chance, "Common should drop with luck")
		for i = 2, #base do
			t.expect(lucky[i].chance > base[i].chance, base[i].id .. " should rise with luck")
		end
	end)

	t.test("pity guarantees Epic or better and resets", function()
		local rng = Random.new(99)
		for _ = 1, 2000 do
			local id, newPity, used = Gacha.rollRarity(rng, 0, Rarities.PITY_THRESHOLD)
			t.expect(used, "pity should be active")
			t.expect(Rarities.rank[id] >= Rarities.rank.Epic, "pity roll gave " .. id)
			t.equal(newPity, 0)
		end
	end)

	t.test("pity counter climbs on misses", function()
		local alwaysCommon = { NextNumber = function()
			return 0
		end }
		local id, newPity = Gacha.rollRarity(alwaysCommon, 0, 5)
		t.equal(id, "Common")
		t.equal(newPity, 6)
	end)

	t.test("mutation odds sum to 1", function()
		local total = 0
		for _, o in Gacha.mutationOdds() do
			total += o.chance
		end
		t.near(total, 1, 1e-9)
	end)

	t.test("jackpot tip needs condition 90", function()
		local rng = Random.new(7)
		for _ = 1, 20000 do
			t.expect(Gacha.rollTip(rng, 89) ~= "Jackpot", "jackpot below 90")
		end
		local jackpots = 0
		for _ = 1, 20000 do
			if Gacha.rollTip(rng, 95) == "Jackpot" then
				jackpots += 1
			end
		end
		t.near(jackpots / 20000, 0.02, 0.006, "jackpot rate")
	end)
end
