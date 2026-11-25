# Fragile Freight — Game Design Doc

Nov 24, 2026 · Roblox Creations

Fragile Freight is a physics-based delivery game for 1–4 players: carry randomly rolled, breakable packages across a town on a ragdoll body, and get paid by how intact they arrive. The skill layer is physics. The luck layer is a gacha on package rarity, mutation and tips, modeled on Steal An Egg and Throw Food For Animals. All numbers here are starting values to tune in playtests.

## 1. Overview

| Field | Value |
|---|---|
| Genre | Physics comedy + collection sim (Roblox subgenres: Physics Sim / Incremental) |
| Players per server | 1–8 (prototype: 1). Fully playable solo. Co-op carries for 2 players. |
| Platforms | Mobile first (most Roblox players), then PC and console. Every control needs a touch equivalent. |
| Session target | 15–30 min. A delivery runs 30–90 seconds. |
| Team | 2 developers using Roblox Studio + Claude Code |
| Content rating target | Minimal / Mild (cartoon slapstick, no blood) |
| References | Steal An Egg (rarity, mutations, base income, light stealing) · Throw Food For Animals (distance-gated biomes, server luck boost, giftable boosts) · Hyper Realistic Ragdoll (physics reaction as the fun) · 100 Miles Down the River (one headline number, light monetization) |

## 2. Core loop

1. **Roll an order.** Walk up to the dispatch board and press Take Order. The server rolls package type, rarity, mutation and destination.
2. **Carry.** The package attaches to your arms with physics constraints. Bumps, falls and tilts damage it.
3. **Deliver.** Enter the drop-off zone. The server scores condition and time, then rolls the customer's tip.
4. **Collect.** The first delivery of each type + rarity + mutation adds it to the Collection Index. Delivered packages can be put on display in your Depot, where they earn passive Coins (the Steal An Egg base-income model).
5. **Upgrade.** Spend Coins on carry stats, luck and new districts, then go back to step 1.

Meta loop: unlock districts (longer, harder routes, better rarity odds) → fill the Index → raise Depot income → earn Depot income offline → come back tomorrow.

Headline number: **Lifetime Tips Earned**, shown on your Depot sign and on a global leaderboard.

## 3. Physics systems

### 3.1 Ragdoll character

- Use a standard R15 rig. The character stays animated (Humanoid-driven) while walking and carrying.
- Trip triggers switch it to ragdoll: an impact above `TRIP_IMPACT_SPEED` (start at 28 studs/s of velocity change), a fall of more than 12 studs, or a hit from a moving hazard.
- To ragdoll: call `Humanoid:ChangeState(Enum.HumanoidStateType.Physics)`, disable each joint's Motor6D, and enable a pre-built BallSocketConstraint per joint with angle limits (LimitsEnabled, UpperAngle about 45° for knees and elbows, 70° for shoulders and hips).
- Recovery: after `RAGDOLL_TIME` (1.2 s), or when the player presses Get Up, restore the Motor6Ds and set the state to GettingUp.
- Ragdoll setup lives in one shared module, RagdollService, so the physics comedy is consistent and easy to tune.

### 3.2 Carry system

- On pickup the package is welded to the character with constraints, not a rigid weld, so it wobbles:
  - An attachment on each hand and two on the package.
  - AlignPosition (Responsiveness about 25, MaxForce tuned per package mass) pulls the package toward a hold point in front of the chest.
  - AlignOrientation (Responsiveness about 15) keeps it roughly upright. Its weakness is what makes tall items tip.
- Package physics properties come from data: mass, size, center-of-mass offset, CustomPhysicalProperties friction and elasticity.
- Network ownership: call `package:SetNetworkOwner(player)` on pickup so the carry feels instant on the client. The server still owns scoring (3.3). On a drop, or on hand-off in a co-op carry, ownership moves to the next carrier, or to the server when nobody holds it.
- Drop rules: the package detaches if the character ragdolls (unless the item is Sticky), if AlignPosition error exceeds `DROP_DISTANCE` (4 studs) for 0.5 s, or if the player presses Drop. A dropped package can be picked back up. Damage keeps accumulating.

### 3.3 Damage model (server-authoritative)

- Every package has Condition from 100 to 0.
- The server samples the package's AssemblyLinearVelocity 20 times per second. A hit is a velocity change (delta-v) above the package's Fragility threshold within one sample.
- `damage = (deltaV - threshold) * FragilityMultiplier * MutationMultiplier`. Also apply tilt damage over time when the package's up vector is more than `TILT_LIMIT` from vertical (liquids and tall items only).
- Don't use `.Touched` as the damage source. It's noisy, and client-owned parts make it exploitable. Use it only for sound and VFX.
- At Condition 0 the package breaks: it plays a break effect, the delivery fails and you get a 10% consolation payout.
- Anti-exploit: the server rejects any delivery where the package moved faster than `MAX_PACKAGE_SPEED`, teleported more than X studs between samples, or arrived faster than the route's minimum time.

### 3.4 Package archetypes (prototype set: Tall, Liquid, Long)

| Archetype | Physics behavior | Main risk | Example items |
|---|---|---|---|
| **Tall** | High center of mass, weak AlignOrientation | Tipping | Wedding cake, lamp, trophy |
| **Liquid** | Tilt damage, slosh (a sloshing mass inside, or a scripted COM shift) | Tilt | Fish tank, soup pot, paint |
| **Long** | Wide size, catches on doorways and poles | Collisions | Ladder, surfboard, carpet roll |
| Heavy | High mass, slows you, trips you on slopes | Falls | Anvil, safe, bowling balls |
| Alive | Random impulses every 1–3 s | Squirming | Cat carrier, chicken, goldfish bowl |
| Co-op (2 players) | Two hold points, one per player, each needs a carrier | Coordination | Couch, piano, giant TV |

## 4. Gacha (luck) system

All rolls run on the server with `Random.new()`. The client only shows results. Luck changes what you carry and what you're paid, never whether the physics works. Condition is always skill.

### 4.1 Rarity roll (per order)

| Rarity | Base weight | Value multiplier | Fragility multiplier | Depot income |
|---|---|---|---|---|
| Common | 60 | 1× | 1.0 | Low |
| Uncommon | 25 | 1.8× | 1.1 | |
| Rare | 10 | 3.5× | 1.25 | |
| Epic | 4 | 8× | 1.4 | |
| Legendary | 0.9 | 25× | 1.6 | |
| Mythic | 0.1 | 100× | 1.8 | High |

- Luck: each non-Common weight is multiplied by (1 + Luck). Luck comes from upgrades, district bonus, the server boost and passes.
- Pity: after 40 orders without Epic or better, the next order is guaranteed Epic or better. Save the counter in player data.
- Reveal: a 1.5 s crate-open animation at the dispatch board with a rarity color flash, plus a server-wide announcement for Legendary and above.

### 4.2 Mutation roll (independent, per order)

| Mutation | Chance | Pay multiplier | Physics change |
|---|---|---|---|
| None | 85% | 1× | — |
| Golden | 5% | 2× | Gold material, +20% mass |
| Glass | 4% | 3× | Fragility ×2 |
| Bouncy | 3% | 1.5× | High elasticity, bounces off walls |
| Haunted | 2% | 2.5× | Random impulses, floats slightly |
| Rainbow | 1% | 5× | Cosmetic only. The "jackpot" mutation. |

Every mutation must change how the carry feels, except Rainbow, which is pure jackpot.

### 4.3 Customer tip roll (at delivery)

| Mood | Chance | Tip | Condition required |
|---|---|---|---|
| Grumpy | 40% | 0% | — |
| Normal | 45% | +10% | — |
| Generous | 13% | +30% | — |
| Jackpot | 2% | +200% | 90 or higher |

The Jackpot condition gate is deliberate: it rewards a clean carry with a bigger roll, so skill and luck stack instead of competing.

### 4.4 Odds disclosure

Show every odds table in-game, behind an info button on the dispatch board. Roblox requires odds for paid random items, and the luck boosts are paid, so showing all odds is the simplest way to stay compliant.

## 5. Economy and progression

### 5.1 Payout formula

```
payout = BaseValue[type] × RarityMult × MutationMult × (Condition / 100)^1.5 × TimeBonus
tip    = payout × TipPercent (from the 4.3 roll)
```

TimeBonus is 1.25 under par time, falling to 1.0 at 2× par. A broken package pays 10% of BaseValue.

### 5.2 Depot (passive income)

- After delivery, the player can keep a "receipt copy" of the package on a Depot display slot, which yields `BaseValue × RarityMult × MutationMult × 0.02` Coins per minute.
- Start with 3 slots, buyable up to 20. Offline earnings are capped at 8 hours. Show "While you were gone: +X" on join.

### 5.3 Upgrades (Coins)

| Upgrade | Effect | Levels |
|---|---|---|
| Grip | +MaxForce and +Responsiveness on AlignPosition | 10 |
| Balance | +TRIP_IMPACT_SPEED (harder to trip) | 10 |
| Sneakers | +WalkSpeed (16 → 22) | 6 |
| Lucky Hat | +Luck (0 → +0.5) | 10 |
| Hand Truck (tool) | Carry Heavy items on wheels; slower but stable | 1 |
| Depot Slots | +1 slot | 17 |

### 5.4 Districts

| District | Unlock | Hazards | Luck bonus |
|---|---|---|---|
| Suburbs | Start | Curbs, sprinklers, dogs | +0 |
| Downtown | 5K Coins | Traffic, crowds, revolving doors | +0.1 |
| The Docks | 50K | Wet planks, forklifts, gaps | +0.25 |
| Mountain Road | 500K | Steep slopes, wind, rockfalls | +0.5 |
| Space Station (update) | 5M | Low gravity, airlocks | +1.0 |

### 5.5 Social and light PvP (optional)

- Co-op carries: 2-player items pay 1.5× each and only spawn when a friend is in the server (or with an NPC helper bot for solo players, added later).
- Server Rush Hour: a paid boost that gives +1 Luck to everyone in the server for 15 minutes, with the buyer's name announced.
- Porch Pirates (phase 3, opt-in): in Downtown only, players with PvP turned on can bump other couriers to make them drop their package, then deliver it themselves for 50% of the pay. Off by default to protect solo play.

## 6. Technical architecture

Rule: **the server decides everything that pays.** Rolls, condition, payouts and data all live on the server. The client handles input, the carry feel and UI.

### 6.1 Project layout

Rojo + Git. See the README for the current tree.

### 6.2 Remotes

| Remote | Direction | Payload | Server validation |
|---|---|---|---|
| RequestOrder | Client → server | none | In the dispatch zone, no active order, cooldown passed |
| OrderRolled | Server → client | type, rarity, mutation, destination | — |
| RequestPickup / RequestDrop | Client → server | package id | Owner or co-op partner, within reach |
| ConditionUpdate | Server → client | condition (throttled to 5/s) | — |
| DeliveryResult | Server → client | payout, tip mood, new Index entry | — |
| BuyUpgrade / SetDisplaySlot | Client → server | id | Price, ownership |

### 6.3 Saved data (per player)

```lua
{
  version = 1,
  coins = 0, lifetimeTips = 0,
  upgrades = { grip = 0, balance = 0, sneakers = 0, luckyHat = 0, handTruck = false },
  districts = { suburbs = true },
  index = { ["cake_rare_golden"] = true },
  depot = { slots = 3, displayed = { {id = "cake", rarity = "Rare", mutation = "Golden"} } },
  pity = 0, lastOnline = 0
}
```

Use session locking (ProfileStore, or DataStoreService with your own lock) so that data can't be duplicated by server hopping. Save on leave, on server shutdown (`game:BindToClose`) and every 2 minutes.

## 7. Monetization

| Item | Type | Price (Robux, to tune) | Notes |
|---|---|---|---|
| Server Rush Hour | Dev product | 99 | +1 Luck for the whole server for 15 min. Giftable feel. |
| Coin packs | Dev product | 25–499 | Standard |
| 2× Coins | Game pass | 199 | Standard |
| Lucky Courier | Game pass | 249 | +0.25 permanent Luck |
| +5 Depot Slots | Game pass | 149 | |
| Gold Hand Truck | Game pass | 99 | Cosmetic + stability |

Nothing sold may raise Condition or skip the carry: buyers get luck and speed, not a free delivery. Handle every purchase in `MarketplaceService.ProcessReceipt`, idempotent by PurchaseId.

## 8. Milestones

Suggested split: Dev A owns physics (section 3). Dev B owns the gacha, economy, data and UI (sections 4–7). Pair up for anti-exploit and playtests.

| Milestone | Scope | Exit test |
|---|---|---|
| M0 Prototype (week 1) | One gray-box street, cake + fish tank + ladder, carry, damage, payout screen. No saving, no gacha. | 5–10 friends play. Do most start a 3rd delivery without being asked? |
| M1 Luck layer (weeks 2–3) | Rarity + mutation + tip rolls, reveal animation, Index, saving, Depot | Do testers chase rare orders, and do sessions get longer? |
| M2 Content (weeks 4–5) | Downtown district, upgrades, shop, 10+ items, icon + thumbnail | Internal 30-minute sessions without boredom |
| M3 Launch (week 6) | Co-op items, Server Rush Hour, leaderboard, analytics, mobile pass | Launch on a Friday. Post 3 short clips that week. |
| Live | An update every 1–2 weeks, on Fridays, with "UPD" in the title | Track CCU before and after each update |

## 9. Analytics

Log custom events with AnalyticsService.

- Funnel: joined → first order → first delivery → third delivery → first upgrade bought.
- Per delivery: archetype, rarity, mutation, final condition, time, broke (yes/no).
- Tuning flags: a break rate above 50% for an archetype means it's too hard; average condition above 90 means it's too easy.

## 10. Open questions to settle in playtests

- Is the carry fun without luck? (M0 answers this. If not, change the physics before adding anything else.)
- Is 30–90 seconds the right delivery length on mobile?
- Does the Depot pull players back, or do they only care about deliveries?
- Does Porch Pirates PvP add fun or drive solo players away?
- Can 8 players with physics packages hold 60 fps on low-end phones? Profile this in M2.
