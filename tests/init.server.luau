-- Tiny spec runner (no dependencies). Build with test.project.json; results print to Output.
-- Each *.spec module returns function(t) and calls t.test(name, fn).

local passed, failed = 0, 0

local function makeT(suite: string)
	local t = {}
	function t.expect(cond: any, message: string?)
		if not cond then
			error(message or "expectation failed", 2)
		end
	end
	function t.equal(a: any, b: any, message: string?)
		if a ~= b then
			error(string.format("%s: expected %s, got %s", message or "equal", tostring(b), tostring(a)), 2)
		end
	end
	function t.near(a: number, b: number, tolerance: number, message: string?)
		if math.abs(a - b) > tolerance then
			error(string.format("%s: %.5f not within %.5f of %.5f", message or "near", a, tolerance, b), 2)
		end
	end
	function t.test(name: string, fn: () -> ())
		local ok, err = pcall(fn)
		if ok then
			passed += 1
		else
			failed += 1
			warn(string.format("[FAIL] %s > %s: %s", suite, name, tostring(err)))
		end
	end
	return t
end

for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") and child.Name:match("%.spec$") then
		local ok, err = pcall(function()
			require(child)(makeT(child.Name))
		end)
		if not ok then
			failed += 1
			warn(string.format("[FAIL] %s did not load: %s", child.Name, tostring(err)))
		end
	end
end

print(string.format("[Tests] %d passed, %d failed", passed, failed))
