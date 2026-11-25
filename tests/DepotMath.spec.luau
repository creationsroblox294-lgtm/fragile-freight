return function(t)
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local DepotMath = require(Shared.DepotMath)
	local Depot = require(Shared.Config.Depot)
	local Packages = require(Shared.Config.Packages)

	local cake = { id = "cake", rarity = "Rare", mutation = "Golden" }

	t.test("per-minute income follows the GDD formula", function()
		local expected = Packages.cake.baseValue * 3.5 * 2 * Depot.INCOME_FACTOR
		t.near(DepotMath.perMinute(cake), expected, 1e-9)
	end)

	t.test("invalid items earn nothing", function()
		t.equal(DepotMath.perMinute({ id = "nope", rarity = "Rare", mutation = "None" }), 0)
	end)

	t.test("offline earnings cap at 8 hours", function()
		local now = 1_000_000_000
		local capped = DepotMath.offlineEarnings({ cake }, now - 24 * 3600, now)
		local eight = DepotMath.offlineEarnings({ cake }, now - Depot.OFFLINE_CAP_SECONDS, now)
		t.equal(capped, eight)
		t.expect(eight > 0, "should earn something")
	end)

	t.test("new players and clock skew earn nothing offline", function()
		t.equal((DepotMath.offlineEarnings({ cake }, 0, 100)), 0)
		t.equal((DepotMath.offlineEarnings({ cake }, 200, 100)), 0)
	end)

	t.test("weakest index picks the lowest earner", function()
		local items = {
			cake,
			{ id = "ladder", rarity = "Common", mutation = "None" },
			{ id = "fishTank", rarity = "Epic", mutation = "None" },
		}
		t.equal(DepotMath.weakestIndex(items), 2)
	end)
end
