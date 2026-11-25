# Fragile Freight

Physics-based delivery game for Roblox. Carry breakable packages across town on a ragdoll
body and get paid by how intact they arrive. Design doc: [docs/GDD.md](docs/GDD.md).

**Status: M0 prototype.** It has one gray-box street, the cake, fish tank and ladder, the
carry, server-side damage, ragdoll and the payout screen. There is no saving and no gacha yet.

## Setup (once per machine)

1. Install [Aftman](https://github.com/LPGhatguy/aftman) (or Rokit), then run this from the repo root:
   ```bash
   aftman install
   ```
   This installs Rojo, Selene and StyLua at the versions in `aftman.toml`.
2. In Roblox Studio, install the Rojo plugin (Plugins → Manage Plugins, or run `rojo plugin install`).

## Run it

```bash
rojo serve
```

Then in Studio, open a new Baseplate, go to the Rojo plugin, and click **Connect**. Press **Play**.
The server builds the map from code (`src/server/MapBuilder.luau`), so the place file is
empty apart from what Rojo syncs. Delete the default Baseplate part so it doesn't overlap
the map.

To build a place file without Studio running:
```bash
rojo build -o FragileFreight.rbxl
```

Lint and format:
```bash
selene src && stylua src
```

## How to play (M0)

| Action | PC | Gamepad | Touch |
|---|---|---|---|
| Take order | E at the blue Dispatch board | ButtonX (prompt) | tap the prompt |
| Drop package | Q | ButtonX | Drop button |
| Turn package 90° (fit the ladder through doors) | R | ButtonY | Turn button |
| Pick a dropped package back up | E | prompt | tap the prompt |
| Get up after tripping | Space | ButtonA | Get Up button |

Follow the green beam to the customer. Hazards include curbs, speed bumps, lamp posts, the
red sweeper bar, the crossing car, the Bakery's narrow door and the Pet Shop stairs.

## Layout

```
src/
  server/            ServerScriptService.Server
    init.server.luau   boot + wiring
    MapBuilder         gray-box street, drop zones, hazards
    CharacterService   ragdoll (server side), collision groups on characters
    PackageService     spawn, carry constraints, network ownership, 20 Hz damage sampling
    OrderService       dispatch board, order lifecycle, delivery detection
    PayoutService      scoring, anti-exploit checks, leaderstats Coins
    CollisionGroups
  client/            StarterPlayerScripts.Client
    init.client.luau
    CarryController    drop / turn input
    RagdollController  trip detection, Humanoid state, Get Up
    UI/Hud             condition meter, order panel, buttons, result card, waypoint beam
  shared/            ReplicatedStorage.Shared
    Config/Tuning      every tunable number in one place
    Config/Packages    item data (mass, fragility, tilt, visuals)
    RagdollService     Motor6D <-> BallSocketConstraint swap
    Scoring            pure math: impact delta-v, tilt, time bonus, payout
    Remotes
```

## Design notes / deviations from the GDD

- **Impact delta-v ignores gravity.** A package in free fall gains `g*dt` of speed every
  sample, and one at rest gains none. `Scoring.impactDeltaV` takes the smaller of the raw
  change and the gravity-compensated change. Both cases read about 0, and a real impact
  still reads high on both.
- **Trips are detected on the owning client**, because it simulates its own character and sees
  impacts first. The client also swaps joints locally on that frame. The server repeats the
  swap so everyone sees the fall, and it drops the package. Hazards ragdoll from the server
  and send the fling impulse to the client, because only the owner can apply impulses.
- **Impact trips need two signals**: a large horizontal velocity change *and* a velocity far
  from where the Humanoid is steering. Without the second check, reversing direction at
  full speed would trip you.
- **The package spawns at the hold point**, with a 0.75 s damage grace period after pickup or
  turning, so the grip snapping into place never costs condition.
- **Pickup uses a ProximityPrompt** instead of a `RequestPickup` remote. It already works on
  touch, gamepad and PC, and the server gets the trigger with range enforced. Drop and Turn
  are remotes.
- **Turn (R)** was added because the 11-stud ladder can't fit through the Bakery's 7-stud
  door otherwise.
- **Anti-exploit flags void the delivery and `warn()`** instead of kicking the player. A wild
  physics fling during a playtest then shows up in the output and doesn't punish the tester.
  Check the output for `[PackageService] ... flagged` when tuning `MAX_PACKAGE_SPEED`.
- **Analytics are printed** for M0 (`[Delivery] ...` lines). They move to AnalyticsService in M2.

## Next (M1)

GachaService (rarity, mutation, tip, pity), the reveal animation, the Index, DataService with
session locking, and the Depot. The order already carries `rarityMultiplier`,
`mutationMultiplier` and `tipPercent`, all set to 1 or 0 for now.
