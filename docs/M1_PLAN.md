# M1 build plan (overnight runs)

Source of truth for the design: [GDD.md](GDD.md). This file is the work queue for unattended
cloud runs. **Each run does exactly one unchecked task, top to bottom, then checks it off and
adds a line to the log at the bottom.**

## Rules for every run

1. Work on branch `claude/beautiful-rubin-4ddb6t`. `git pull` first; `git pull --rebase` again
   right before pushing. Never push to any other branch. Never force-push.
2. One task per run. If a task is too big, split it into `Na` / `Nb` items in this file, do
   the first part, and leave the rest unchecked.
3. **The game must still run after every run.** Nobody can run Studio overnight, so there is
   no Luau runtime here. Read your diff back slowly, check every `require` path against the Rojo
   tree in `default.project.json`, check every remote name against `src/shared/Remotes.luau`,
   and check Roblox API names you are not certain of in the Roblox docs (create.roblox.com/docs).
   Run `python3 scripts/build_rbxlx.py` to confirm the tree still builds.
4. Server decides everything that pays (GDD §6). All rolls use `Random.new()` on the server.
   Validate every remote argument by type and range. Rate-limit client → server remotes.
5. Every tunable number goes in `src/shared/Config/`. No magic numbers in services.
6. Pure logic (rolls, payout, income math) goes in modules with no Roblox service calls,
   with an injectable RNG, so it can be unit tested. Add specs under `tests/` (TestEZ style,
   `*.spec.luau`) for each pure module.
7. **No made-up asset IDs.** Don't use an `rbxassetid://` unless it's already in the repo or
   is a documented built-in. Build visuals from parts, materials, Beams, ParticleEmitters
   (default texture), Highlights, UI gradients and strokes, and procedural tweens.
8. Mobile first: every new interaction needs a touch path (button or ProximityPrompt), and
   UI must scale (UIScale or scale-based sizes, safe-area aware).
9. Use the roblox-dev skills when relevant (roblox-security, roblox-datastores, roblox-ui,
   roblox-performance, roblox-testing), and run the `roblox-dev:roblox-reviewer` agent on your
   diff before committing. Fix what it finds that's real.
10. Commit with a clear message, push, update README if behavior or controls changed.
11. M0 playtest tuning (cake etc.) may be changed by the humans in parallel. Don't revert
    their tuning numbers.

## Tasks

- [ ] **1. Gacha core.** `Config/Rarities.luau`, `Config/Mutations.luau`, `Config/Tips.luau`
  with the GDD §4 tables (including colors per rarity for UI). Pure `shared/Gacha.luau`:
  weighted rarity roll with Luck (non-Common weights × (1 + luck)), pity (40 orders without
  Epic+ → guaranteed Epic+), independent mutation roll, tip roll with the Jackpot condition
  gate (≥ 90; re-roll into the other moods if gated). Server `GachaService` wraps it with a
  per-player pity counter (in memory until DataService exists). Specs for distribution
  sanity (seeded RNG, 100k rolls within tolerance), pity, and the jackpot gate.
- [ ] **2. Wire rolls into orders + mutation physics.** OrderService uses GachaService.
  Rarity multiplies value and fragility (GDD §4.1). Mutations change the carry (GDD §4.2):
  Golden = gold material, +20% mass. Glass = Glass material, fragility ×2. Bouncy = high
  elasticity. Haunted = random impulses every 1–3 s plus slight float. The holder's client
  applies the impulses, because it owns the physics. When nobody holds it, the server applies
  them. Rainbow = cosmetic only (animated hue). Tip roll at delivery feeds `tipPercent`.
  `OrderRolled` and `DeliveryResult` carry rarity, mutation and tip mood. The result card
  shows the tip mood.
- [ ] **3. Reveal + rarity juice.** 1.5 s crate-open reveal at the dispatch board (crate model
  shakes, lid pops, rarity color flash + particles, then the package flies to your hands).
  Rarity glow on carried packages (Highlight outline in rarity color; sparkles for
  Legendary/Mythic). Server-wide announcement banner for Legendary+.
- [ ] **4. DataService (saving).** DataStoreService with session locking via UpdateAsync
  (lock owner = JobId + timestamp, steal after 30 min stale), retry with exponential backoff,
  autosave every 2 min, save on leave and in `game:BindToClose`, schema `version = 1` from
  GDD §6.3 plus a migration hook. Coins, lifetimeTips, pity, index, depot, upgrades persist.
  Works in Studio with API access off: fall back to in-memory data, warn once.
  Leaderboard stat: Lifetime Tips (leaderstats).
- [ ] **5. Collection Index.** First delivery of each type + rarity + mutation is recorded
  (server, saved). "NEW!" stamp on the result card. Index panel (button on HUD): grid by
  package × rarity, mutation pips, completion %. Locked entries as silhouettes.
- [ ] **6. Depot.** A Depot building next to the dispatch area with display pedestals.
  After a delivery, the result card offers "Display in Depot" if a slot is free (or swap).
  Each displayed item earns `BaseValue × RarityMult × MutationMult × 0.02` coins per minute
  (Config), and a floating label shows its rate. Offline earnings use `lastOnline` and are
  capped at 8 h, shown on join as "While you were gone: +X". The Depot sign shows Lifetime
  Tips. Pure income math goes in a tested module.
- [ ] **7. Odds screen.** An info button on the dispatch board and HUD opens every odds table
  (rarity with your current luck applied, mutation, tips) (GDD §4.4).
- [ ] **8. Visual pass on the town.** Turn the gray box into a stylized suburb. Houses get
  pitched roofs, doors, windows and porches. Add trees, hedges, fences, mailboxes, road
  markings and crosswalks. Lighting: Atmosphere, Sky color via Lighting properties, Bloom,
  ColorCorrection, a warm afternoon ClockTime. Keep collision shapes simple, mark decor
  `CanCollide = false` where it doesn't matter, and stay within a sensible part budget for
  mobile. Hazards stay readable: bright, striped.
- [ ] **9. Game feel.** Impact feedback: spark particles at the hit point, a short camera
  shake scaled by damage, condition bar shake and red flash, floating "-12" numbers. Coin
  burst and count-up on delivery. Character arms reach for the package (IKControl on both
  arms toward attachments on the package's sides). Break effect: more pieces, confetti-like
  crumbs in the package's colors.
- [ ] **10. Physics polish.** Fish tank slosh: a scripted center-of-mass shift that lags
  the carrier's acceleration and feeds the tilt. Tune AlignOrientation per archetype so Tall
  wobbles visibly but is carryable. Add the Get Up stand-up so it doesn't pop. Add one
  **Alive** item (cat carrier: random impulses every 1–3 s, client-applied while held) and
  one **Heavy** item (anvil: high mass, slows you, trips you on slopes). Data only in
  `Config/Packages.luau`, plus whatever generic behavior hooks they need.
- [ ] **11. Hardening + review.** Run the roblox-reviewer agent over the whole `src/`. Fix
  remote validation gaps, connection leaks (players leaving mid-order, character respawn),
  and any per-frame allocations in hot loops. Update README (controls, systems, how to test
  saving in Studio).

## Log

<!-- One line per run: date/time UTC, task, commit hash, anything the humans should know. -->
