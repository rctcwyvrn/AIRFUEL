# Airfuel — Design Document

**Status:** Pre-production. Nothing is built.
**Last updated:** 2026-09-08

---

## Table of Contents

1. [Premise](#1-premise)
2. [Design Pillars](#2-design-pillars)
3. [Core Loop](#3-core-loop)
4. [Movement System](#4-movement-system)
5. [Airfuel Economy](#5-airfuel-economy)
6. [Respawn & Repositioning](#6-respawn--repositioning)
7. [Combat: The Arm System](#7-combat-the-arm-system)
8. [Weapons](#8-weapons)
9. [Damage & Health](#9-damage--health)
10. [Upgrades](#10-upgrades)
11. [Loadouts](#11-loadouts)
12. [Game Modes](#12-game-modes)
13. [Objective Rules](#13-objective-rules)
14. [Map Design](#14-map-design)
15. [HUD, UI & Information](#15-hud-ui--information)
16. [Audio](#16-audio)
17. [Feel & Feedback](#17-feel--feedback)
18. [Art Direction](#18-art-direction)
19. [Servers, Modding & SDK](#19-servers-modding--sdk)
20. [Technical Plan](#20-technical-plan)
21. [Monetization](#21-monetization)
22. [Known Risks](#22-known-risks)
23. [Open Questions](#23-open-questions)
24. [Prototype Roadmap](#24-prototype-roadmap)
25. [Appendix A: Cut Ideas](#appendix-a-cut-ideas)
26. [Appendix B: Tuning Variables](#appendix-b-tuning-variables)

---

## 1. Premise

Airfuel is a free-to-play 3D first-person shooter built around a single idea:
**air is a resource, and geometry is where you refill it.**

Players fight in a low-gravity corridor. Every act of mobility beyond running —
dashing, double jumping, air-strafing, lunging — spends Airfuel. Airfuel comes
back one way: by wallrunning. Skilled players move in a rhythm of wall contact
and airborne commitment; unskilled players end up grounded in the open.

Weapons are lethal, few, and loudly telegraphed. There is no health regeneration,
no chip damage, and no partial commitment. Every kill is something the victim
could have seen coming and failed to answer.

Death is cheap and constant. You are launched back into the fight from a cannon
you aim yourself.

Teams fight over a single neutral bomb at the centre of a long corridor and try
to carry it into the enemy's base. Because you carry it *away* from your own
spawn, defense is advantaged and scoring requires a real, coordinated push.

The game does not take itself seriously visually. It takes itself extremely
seriously mechanically.

---

## 2. Design Pillars

**1. Air is a resource; walls are the refill.**
The fuel economy is the spine. Every other system is tuned in relation to it.
Maps are authored around it. Weapons that interact with it do so deliberately.

**2. Nothing lethal is silent.**
Every kill mechanism announces itself before it lands — a charge sound, a
narrowing aim cone, a proximity warning, a visible arc. Dying to something you
had no chance to perceive is a bug, not a difficulty setting.

**3. Commitment over flexibility.**
No partial charges. No cancels. No chip damage. No hedging. You commit, and you
are right or you are dead. High skill, high risk, in every system.

**4. Movement is the reward.**
Progression, stats, and cosmetics are not the retention mechanism. Getting
better at moving is. The game's job is to make a well-executed wallrun chain
feel better than a level-up.

**5. Never stuck.**
The player should never be stranded, bored, or out of options. Instant respawn,
instant teleport home, walls everywhere, and a cannon that puts you back in the
fight facing wherever you chose.

---

## 3. Core Loop

**Second-to-second:** wallrun to build speed and fuel -> launch into open space ->
spend fuel dodging and repositioning -> find a wall before you run dry.

**Engagement-to-engagement:** read the telegraph -> commit a dodge or commit a
shot -> kill or die -> relaunch from the cannon or teleport home to reset.

**Match-to-match:** contest the neutral bomb at midfield -> escort it forward into
enemy territory -> breach their base and plant it.

The tension the player feels at any given moment is *how much air do I have
left, and how far am I from a wall?*

The match has three distinct phases, which is the main structural argument for
the bomb-carry direction (see Appendix A): a **fight** for the object at center,
a **push** down the corridor, and a **breach** of a defended position. The old
carry-it-home direction only had the first phase, because winning midfield made
the score nearly automatic.

## 4. Movement System

### 4.1 Baseline

- **Low gravity.** Floaty in the sense of long arcs, but movement is
  **extremely fast**. This is Tribes-fast, not moon-jump-slow. Hang time exists
  so you can act in the air, not so you can be a slow target.
- **Running** is free. Everything else costs Airfuel.
- **Terminal velocity** exists and is enforced. Wallrun chaining accelerates
  you, but there is a hard ceiling. Without it, a long corridor plus low gravity
  plus escalating wallrun speed produces an unbounded acceleration exploit.

### 4.2 Wallrun

The centerpiece. Wallrun is free (costs no Airfuel) and is the only way to
refuel.

- **Chaining is the skill.** Reward is granted **on dismount**, not on duration.
  A short, fast wallrun into another short, fast wallrun should out-perform one
  long ride. Long single runs give diminishing returns.
- **Dismount grants:** a chunk of Airfuel, plus a **speed boost** scaled to how
  fast you were moving along the wall. Slow wall-hugging to top off the meter
  gives near-nothing.
- **Momentum carries** off the wall into the air.
- **Ramp persistence across gaps:** a short grace window after dismount preserves
  accumulated speed, so a clean transition to the next surface compounds. Miss
  the window and the ramp decays. This is what makes chaining the high-skill line
  rather than "find the longest wall."
- **Design target:** at high skill, wallrunning from your own base should be
  *faster* than taking the respawn cannon. Traversal should be a skill
  expression, not a loading screen.
- **Curved surfaces** (the signature cylindrical platforms) must be
  wallrunnable. This is a technical risk — see §22.

### 4.3 Air Dash

- Costs Airfuel. The primary evasive tool.
- Omnidirectional.
- The counter to a charging railgun: you see the tell, you dash on the beat.

### 4.4 Down Dash

Universal, available to everyone. Costs Airfuel.

Its jobs:
- Break line of sight by dropping through a vertical layer.
- Cut hang time when you're an exposed target.
- **Reach a wall fast** — it is the primary tool for getting back to the fuel
  economy when you're low and airborne.

Replaced the earlier "personal gravity" concept. Chosen for legibility: it reads
instantly, it's one ability instead of a held state, and it does the same jobs.

### 4.5 Double Jump / Air Strafe

Airfuel-costed air control. Strafe adjustments to a jump arc, and a mid-air jump.
These are the small, cheap expenditures; the dash is the large one.

### 4.6 Sword Lunge

See §8.2. A movement ability that is also a kill. Costs Airfuel, but is
**cheaper per meter and longer than a normal dash**, on a per-arm cooldown.

---

## 5. Airfuel Economy

### 5.1 Rules

| Action | Effect on Airfuel |
|---|---|
| Running, wallrunning | Free |
| Air dash | Cost |
| Down dash | Cost |
| Double jump / air strafe | Small cost |
| Sword lunge | Cost (cheaper per meter than a dash) |
| **Wallrun dismount** | **Refill (scaled to speed)** |
| Kill | Nothing |
| Death | Nothing |
| Teleport home | Full refill (part of the reset) |

**Wallrunning is the only in-play refill.** This was the single most important
correction in development. Earlier drafts refilled on death and on kills; both
were cut.

### 5.2 Why kills and death were cut as refills

- **Kill-refuel snowballs.** The player winning fights got the mobility to keep
  winning fights.
- **Death-refuel makes suicide optimal.** If dying refills your tank and respawn
  is instant, killing yourself becomes a resource decision, and the movement
  system is bypassed by a keybind.
- **Wallrun-only makes the map load-bearing.** The cylindrical platforms and
  corridor geometry stop being scenery and become the economy. Running dry means
  you overextended across open ground — a positional mistake with a positional
  fix.
- **Nobody is ever stranded.** There's always a wall. The "helpless grounded
  player" problem solves itself without needing death as an escape hatch.

### 5.3 Generosity

Airfuel should be **generous**. The fantasy is lots of mobility, constantly. The
resource is a rhythm constraint, not a scarcity constraint — it should shape
*how* you move, not stop you from moving. Running completely dry should be a
notable failure state that happens a few times a match, not a constant condition.

### 5.4 Bomb carrier exception

The bomb carrier does not use Airfuel. See §13.4.

---

## 6. Respawn & Repositioning

There are two ways to reset your position, and they map cleanly onto the two
sides of the objective:

- **The respawn cannon is the offense's reset.** It launches you forward, and it
  extends further when your team is pushing.
- **Teleport home is the defense's reset.** It snaps you back to the point you
  are defending.

Each is close to useless for the other job. That symmetry is deliberate.

### 6.1 Respawn Cannon

On death you are loaded into your team's cannon and launched.

- **You aim it.** You choose your landing point along the corridor from your end.
- **Enemies see the trajectory.** Your arc is public. Flying into the open is an
  inherent, chosen risk.
- **You can act mid-flight.** You can fire your weapons. Charging a railgun
  **slows you from cannon speed down to normal (still fast) speed** -- the charge
  doubles as an air brake, which is a real repositioning tool and a real cost.
- **You can spend Airfuel to halt or redirect** mid-flight.
- **You can decline the cannon.** Staying at your own end on foot is a legal
  choice, and the correct one when you have teleported home to defend.
- **No spawn invulnerability.** Launching well and dodging incoming fire is skill
  expression. You are killable in the arc.

**Baseline range:** the first quarter of the map from your own end.

**Push lever:** the team **carrying the bomb** gets **extended cannon range**,
letting them launch deeper to rejoin the push. This is the attacker's lifeline,
because their teleport sends them the wrong way (see 6.2) and a dead attacker is
otherwise removed from the play entirely.

This is **asymmetric** -- only the carrying team gets the extension. If both teams
got it, it would cancel out.

> **Open:** the extended range and the *defending* team's launch zone are the
> same airspace, which creates spawn pressure on the defenders' exits. Either the
> extension stops short of the defenders' launch zone, or defender exits get
> geometric protection. See section 23.

### 6.2 Teleport Home

A free, instant keybind. Framed not as suicide but as **"teleport back home"** --
it should feel good, not like a failure.

- **Instant.** No cast, no delay.
- **Heals you to full.** With no regeneration in the game, this is the only heal.
- **Refreshes your loadout** -- you may swap weapons and upgrades.
- **Takes you to your own end**, which is also the point you are defending.
- **Then relaunches you** from the cannon, or you can decline and stay on foot.
- **Visible to the enemy.** Their UI shows that someone teleported home, so the
  attacking team gets the information that defense is rotating.
- **The bomb carrier cannot teleport.**

### 6.3 Teleport jamming (required by the bomb-carry direction)

**Proposed rule: you cannot teleport home while an enemy carries the bomb toward
your base.**

Under the old carry-it-home objective, teleport needed no constraint, because it
sent you *backward* -- away from an enemy carrier who was running away from you.
It was anti-useful for chasing and therefore self-balancing.

Inverting the objective inverts that reasoning completely. The carrier now runs
*toward* your base, which is exactly where teleport puts you. Without a
constraint, defenders snap to the destination instantly, free, healed, with a
fresh gunshield, repeatedly -- while the attacker has to cross the whole corridor
*and* break that wall. That is a harder failure than the one it replaced:
"scoring is too easy" is a mediocre game, "scoring is impossible" is a broken one.

Jamming targets the problem precisely without touching the tool anywhere else,
it is thematically legible (your base is under attack, the teleporter is down),
and it turns the pickup into a dramatic beat -- an alarm sounds and your team's
free reset is gone until you clear it.

**Consequence to watch:** every "once per life" resource in the design refreshes
on a trip home (see section 22). Jamming means the defending team's shields, health
and loadouts stop refreshing at exactly the moment they are under the most
pressure. That is probably correct, but it is a large swing and needs testing.

## 7. Combat: The Arm System

Players have **two independently-firing arm weapons — left arm and right arm.**

There is no separate "primary" and "shoulder mount." Both arms are mechanically
identical mounts. You pick two weapons; they may be the same or different.

- Both fire along the **same crosshair**. One aim point, two triggers.
- Each arm has its own charge state and cooldown.
- This replaced an earlier "shoulder mount" concept that was becoming hard to
  read. Two symmetric arms is simpler to explain, simpler to balance, and
  produces more interesting sequencing.

### 7.1 Dual charging

You may charge both arms. Constraints:

- **You cannot hold a full charge.** A charge auto-fires the instant it completes.
- **You cannot fire both simultaneously.** There must be a meaningful gap.
- Therefore: **you stagger your charge starts.** The gap between your two shots
  is exactly the gap between when you pressed each trigger.

This is deliberate and is one of the better emergent mechanics in the design:
**dual rail is a rhythm instrument.** Fire them close together for a tight,
easily-dodged pair; spread them out to catch someone who dodged early. The
defender sees two tells at different phases and must solve both.

The defender should get a **generous** window between the two shots.

### 7.2 The freeze

Charging a railgun freezes you — you stop moving, or if airborne, you **hold your
current trajectory** and lose the ability to steer. If any charge is active, the
freeze applies. Dual rail therefore means being locked from first trigger press
to second shot: an enormous commitment, playable mainly from hard cover.

You cannot cancel a charge. A mistimed second charge will auto-fire into nothing
while you are rooted.

---

## 8. Weapons

Two weapons. Three loadouts. This is deliberate — a small, complete triangle at
solo-dev scope.

### 8.1 Railgun

Reference feel: the Armored Core 6 railgun. Loud, heavy, committal.

- **Charge time ~1s**, then auto-fires. No holding, no early release, no partial
  damage.
- **Hitscan.** Correct at these movement speeds — a projectile would be
  undodgeable by accident and unaimable on purpose. Hitscan is acceptable here
  *because* of the charge telegraph.
- **Freezes you** (or locks your air trajectory) for the duration of the charge.
- **Aim stays free.** Charging never degrades your turn rate (an earlier "aim
  crush" mechanic did — cut, see Appendix A). What makes the dodge possible is
  the target: the shooter must land a hitscan shot on someone who can dash in
  any of 8 directions at the last instant. Tracking that dash is the skill
  check.
- **Loud.** A charging railgun is audible and directional.
- **Bolt action.** Ejects a spent canister on fire — aesthetic and satisfaction,
  and a load-bearing feedback beat (see §17).
- **Damage:** 2 body / 1 headshot.

**Fixed rhythm is intentional.** Every rail shot takes exactly the same time, so
good players internalize the timing and the dodge becomes reliable. This is a
feature: it means the railgun stops killing people who are paying attention and
starts killing people who are **out of position or out of fuel.** The rail
punishes bad positioning.

### 8.2 Sword

- **One-shot kill** on anyone.
- **Lunge:** each sword arm has a lunge on its own cooldown. The lunge costs
  Airfuel, but is **cheaper per meter and travels further than a normal dash.**
  It is simultaneously the sword's mobility and its kill.
- **No ranged option whatsoever.**
- **Warning system:** melee gets an explicit proximity warning —
  `SWORD NEARBY, ON THIS SIDE` — to prevent unperceivable backstab kills. This
  upholds Pillar 2 and is a direct mitigation for the melee netcode problem
  (see §22).

The sword punishes bad awareness.

### 8.3 Loadout identities

| Loadout | Identity |
|---|---|
| **Rail + Rail** | Static predator. Dual staggered charges, huge commitment, kills from cover. Pairs naturally with the gunshield. |
| **Rail + Sword** | Flexible. A ranged threat and a gap-closer. The generalist. |
| **Sword + Sword** | High mobility. Double lunge is devastating and is also the best traversal kit in the game. Zero range at all. |

**Dual sword is the natural bomb carrier.** The carrier cannot shoot, so "no
range" costs the carrier nothing — and dual sword is the fastest, most
fuel-efficient kit available. This produces a team structure for free:
**swords run, rails cover.** Nobody has to be told this; it falls out of the
rules.

**Dual sword is also the map canary.** It is the only loadout with no ranged
threat, so its viability is a direct readout of whether a map has enough cover.
Unplayable → sightlines too open. Dominant → sightlines too dense.

---

## 9. Damage & Health

### 9.1 Uniform HP

**Every player has the same health.** There are no classes and no
weapon-linked HP.

This was chosen over a frame/chassis system because:
- Two arm weapons made weapon-linked HP incoherent (what's the HP of rail+sword?).
- It removes the requirement for radically distinct silhouettes readable at 80m.
- The damage matrix fits on a card.

A frame/chassis axis (separate HP/mobility pick) remains available as a later
addition if the game feels flat. It is much easier to add than to remove.

### 9.2 The matrix

| | Damage |
|---|---|
| Railgun, body | Half health (2 to kill) |
| Railgun, head | Lethal |
| Sword | Lethal |
| Missile (upgrade) | Lethal |

**No chip damage. No partial charges. No regeneration. No healing pickups.**

The only heal is teleporting home. This is thematically load-bearing: in Airfuel,
**death and going home are maintenance.**

---

## 10. Upgrades

Upgrades are **chosen at loadout**, not contested on the map. One per player.
They are re-selectable whenever you respawn or teleport home.

This replaced an earlier design where upgrades were map objectives you stood on
to capture. That was cut because:
- Standing still is the least interesting thing a player can do in this game.
- It snowballed (winning team gets upgrades, gets more upgrades).
- It split focus away from the single objective.
- It was a large amount of system for a solo developer.

### 10.1 Current upgrade list

- **Gunshield** — see below.
- **Missiles** — lock a target, fire a slow homing missile. One-shot lethal.
  Dodgeable with a well-timed dash, breakable with cover. Limited (per life or
  long cooldown). This is the survivor of the cut Tagger weapon (§Appendix A).
- **Stim** — significant temporary speed increase.
- **Grapple** — must be Airfuel-costed, or it bypasses the wallrun economy.
- **Extra Airfuel / stronger dash** — raw capacity increase.
- **Warpdash** — instant short-range translation.

⚠️ **This list needs rebuilding.** It has been quietly gutted by good decisions
elsewhere: invisibility was cut, personal gravity became the universal down-dash,
and the shoulder mount became the default two-arm system. What remains is thin,
and "extra Airfuel" and "warpdash" are near-duplicates of each other.

### 10.2 Gunshield

The most developed upgrade, and the one that defines an archetype.

- **Actively deployed.** You raise it; it is a choice you time.
- **Forward-facing only.** Flanking is the counter — this is specifically what
  gives swords a job against a shielded rail player.
- **Blocks one hit, including a sword hit from the front.**
- **Does not recharge.**
- **Strict movement penalty** — raising it slows you significantly.
- **You cannot charge while the shield is up.**

That last rule is the important one. It makes the shield **reactive rather than
passive**, and produces a real duel loop: their charge forces your shield up,
which costs you your own charge, which gives them tempo. If you could charge
behind the shield, it would be free armor bolted onto exactly the window dual
rail is vulnerable in — mandatory for rails, useless for swords, and no decision
at all.

Gives dual rail a second viable style: **stand still and tank a hit.**

---

## 11. Loadouts

A loadout is **two arm weapons + one upgrade.**

- **Fluid swapping.** You may change loadout on any respawn or teleport home,
  freely and instantly.
- **Saved loadout presets** you can switch between, so swapping is fast in the
  moment.

**Framing:** this is about **playing what you enjoy**, not about matchup
counter-picking. The intent is that all three weapon configurations are viable
at all times and you pick the one you like. Consequently the game does *not* need
to heavily surface enemy composition — an enemy loadout readout on the scoreboard
is nice-to-have, not a requirement.

---

## 12. Game Modes

### 12.1 6v6 Neutral Bomb -- the main mode

This is the reference mode. Every tuning argument is settled in its favor.

- A single **neutral bomb** spawns at the centerline.
- Either team may carry it.
- Carry it **into the enemy base** and plant it to score.
- **10 minute matches.**
- **Casual target: a small number of scores.** Each score should be a significant
  event, not a tick.
- **Mercy rule** to end lopsided games early.

The direction of travel is the important part. Because you carry the bomb *away*
from your own spawn and *into* the enemy's, the defense is naturally advantaged:
they respawn at the place they are defending, and the bomb comes to them. Scoring
requires a coordinated push rather than a foot race. See Appendix A for why the
opposite direction was abandoned.

### 12.2 1v1 Duel

**No bomb. Straight duels.** A pure test of movement, fuel management, and the
railgun rhythm. Nearly free to build -- same systems, smaller map, no objective
logic.

**Win condition: first to 5 kills** (decided 2026-09-09 at prototype tier —
the hosted lobby server's 1v1s use it; revisit against rounds after
playtests).

Note this means shipping two modes with genuinely different rules, not one mode
at two scales. 6v6 is the priority; 1v1 exists because the combat is good enough
to stand alone.

### 12.3 Ranked

**Best of 3, each game first to 3 scores.** More scores per game than casual means
one lost teamfight is not fatal and there is room for the comeback levers to
operate.

### 12.4 Tiebreak: deepest incursion

When a match ends level on score, **the winner is whichever team carried the bomb
furthest toward the enemy base.**

- Tracked as a **high-water mark** per team -- the deepest point the bomb ever
  reached on each side, not total distance carried.
- Displayed persistently on the map as a marker, so both teams can see how deep
  the enemy got and how much further they need to push.
- If neither team ever moved the bomb, the match is a draw.

This **replaces the sudden-death round entirely** (see Appendix A). It is better
on three counts:

1. **It deletes a whole mode.** No no-respawn ruleset, no shrinking play area, no
   tick damage, no centerline bait upgrades to place and balance. Meaningful
   scope savings for a solo developer.
2. **It is an anti-turtle mechanism.** The moment the enemy walks the bomb to 60%,
   sitting at home means losing the tiebreak. A defensive posture is only viable
   when you are ahead -- which is correct.
3. **It makes 0-0 games interesting.** A scoreless match decided by who pushed
   five metres deeper is dramatic rather than empty, which matters a lot in a
   mode where defense is advantaged and scores are rare.

### 12.5 1v6 (concept, unscheduled)

An asymmetric mode: one fully-upgraded player against six. Cheap to build once
the systems exist, and a strong showcase. Needs its own win condition -- escort,
survive a timer, or hunt all six. Not scoped.

## 13. Objective Rules

### 13.1 The neutral bomb

- Spawns at the centerline.
- Either team may pick it up.
- Carried **into the enemy base** and planted to score.
- **Does not auto-return.** A dropped bomb stays where it fell.
- **It is a two-way ratchet.** Because the bomb is neutral and both teams carry it
  toward the *enemy*, a defender who picks it up at their own doorstep instantly
  becomes a carrier running the other way. Grabbing the bomb near your own base is
  not merely a clear -- it is a counterattack, and the team that was pushing is
  suddenly chasing.

That last property is the strongest argument for keeping the object neutral. In
the old carry-it-home direction, a dropped object sat inert and was simply
contested in place. Here every pickup reverses the direction of play.

### 13.2 The plant

Scoring is not a touch. The carrier must **plant the bomb**, which takes a few
seconds during which they are **stationary and vulnerable**.

- Gives the defense a genuine last stand rather than losing on a wall-touch.
- Makes the final moment of a push contestable, which is where the drama belongs
  after a two-phase attack.
- Is the natural home for the loudest audio and feedback beat in the match.

**Open:** can a defender interrupt a plant in progress by killing the planter, or
does partial progress persist? Interrupt-and-reset is simpler and more dramatic.

### 13.3 Comeback and pacing levers

- **Bomb respawn offset.** After a score, the bomb respawns closer to the trailing
  team. One number, no new systems, scales continuously with the score gap.
- **Extended cannon range for the carrying team** (section 6.1). The attacker's
  lifeline, since their teleport is anti-useful during a push.
- **Teleport jamming for the defending team** (section 6.3). The counterweight
  that stops defense from being free.

These three levers pull against each other and are the main dials for making the
push winnable without making it easy.

### 13.4 The bomb carrier

Deliberately **fast and fragile**, not tanky.

- **Cannot shoot.** No weapon use at all. The carrier is the payload; the team is
  the weapon.
- **Keeps the sword lunge as pure movement** (no damage) if carrying a sword.
  This is what makes dual sword the natural carrier kit.
- **Does not use Airfuel.** Instead, dashes are on a **cooldown**. Simpler than
  "infinite fuel," same result, one less rule.
- **Highlighted through geometry** to the entire enemy team, constantly.
- **Cannot teleport home.**
- Dies as easily as anyone else.

**The carrier's role changed with the direction of travel.** Running toward your
own base made the carrier a solo runner dodging a chase. Running into the enemy
base makes them the **tip of a team push**: escorts clear the ground, the carrier
follows and plants. The moment-to-moment experience is closer to "wait for the
breach, then commit" than "juke through cover."

This is a better team game, but it is a different fantasy from the original
sketch, and it means an unescorted carrier who arrives first simply dies. That is
intended. Do not solve it by arming the carrier -- an unarmed payload the team
protects is a far cleaner role than a carrier who half-fights.

### 13.5 Push structure

Because teleport home sends you to your own end, and the carrier runs toward the
enemy end:

- The **defending team's** teleport lands them exactly where they need to be. This
  is why jamming exists (section 6.3).
- The **attacking team's** teleport sends them backward, away from their own push.
  It is anti-useful during an attack.
- A dead attacker is therefore removed from the push, and rejoins only via the
  cannon -- which is why the carrying team gets the extended range.

**Consequence:** the midfield fight decides who *gets* to push; the breach decides
whether the push *scores*. Both phases matter, which is the improvement over the
previous direction where only the first did.

## 14. Map Design

### 14.1 Shape

**One long, wide corridor.** Neutral bomb at the centerline, capture points and
cannons at each end.

### 14.2 Verticality is the tuning tool

Cover and routing come from **vertical layering**, not from side corridors. The
corridor is better understood as *a cluttered vertical volume shaped like a
corridor* than as an open hallway.

- Layered platforms break sightlines **along** the lane, not just across it.
- The **down dash** is the primary tool for dropping a level to break line of
  sight, which ties movement and map structure together.
- Cylindrical platforms are the signature form and must be wallrunnable.

### 14.3 Sightlines

**Both types of engagement should exist, leaning toward dueling over sniping.**

- Long sightlines make the railgun a map-control weapon and the high ground the
  whole game — and leave the carrier nothing to dodge behind.
- Sight breaks every ~20-30m make the railgun a *dueling* weapon and give the
  carrier and the swords somewhere to live.

Lean toward the second. Platforms are load-bearing cover, not decoration, and
this constrains the art direction accordingly.

### 14.4 Length

The most consequential number in the map.

- The cannon covers the **first quarter** from each end at baseline, further for
  the team carrying the bomb.
- The bomb fight starts at **center**.
- The enemy's end is the **destination**, and is the most contested space on the
  map.

Under the bomb-carry direction, the whole corridor is used: center for the
initial fight, the corridor for the push, the enemy quarter for the breach. (This
is a direct improvement over the old carry-it-home direction, where the outer
quarters were pure chase corridor and the endzone was favored for the attacker,
so roughly half the map was travel time.)

Length now governs **how expensive a push is**. Too long and no push survives
attrition against a defense that respawns on top of the objective; too short and
the defensive advantage evaporates. This number cannot be guessed -- it falls out
of how fast a chained wallrun actually moves, which the movement prototype will
tell us.

### 14.5 Fuel authoring rule

**No open area may be more than roughly one tank of Airfuel from a wallrunnable
surface.** This is a hard constraint on every map, and it is what prevents the
"stranded in the open" failure state.

### 14.6 Cannon exits

Two teams, one lane, two ends, no spawn invulnerability creates an obvious
spawn-camping risk. Mitigations to design in:
- Wide cannon aiming arc, so a camped exit can be avoided by aiming elsewhere.
- Multiple launch exits per end.
- The mercy rule as a backstop.

### 14.7 Map count

**"Every archetype is viable" is a multi-map promise.** A single corridor gives
exactly one balance point, and whichever loadout is optimal there is optimal
forever.

Target: **2–3 shipping maps with genuinely different density profiles** — one
open (rail-favoring), one dense (sword-favoring), one in between — each
carefully balanced for all archetypes rather than being a specialist map.

Server owners can additionally author their own maps, including deliberately
specialized ones (e.g. a rail-only server with rail-optimized geometry). See §19.

---

## 15. HUD, UI & Information

### 15.1 Philosophy

**Dodging is the skill, not reading the map.** The HUD should be rich and
expressive, and it should aggressively surface threats so that the player's
attention goes into movement and timing rather than into scanning.

Audio may be redundant with the UI. That is acceptable — the UI is primary.

### 15.2 Charge warnings

**Warn on every charge.** Any enemy railgun charge produces a loud,
directional warning that escalates with charge progress. Simple, honest, and
nothing to compute — the defender always gets the tell.

The earlier version of this rule filtered warnings by the shooter's aim cone,
which depended on the aim-crush mechanic (the cone narrowed as the charge
built, so the game knew who was actually threatened). Aim crush is cut
(Appendix A), so the cone no longer exists. The known risk of warn-on-every-
charge is 6v6: twelve players charging constantly may turn every tell into
ambient noise. Whether that happens in practice — and what filter would fix
it if so — is deliberately deferred to playtesting (see 23, Combat).

### 15.3 What the HUD surfaces

- Airfuel meter — must remain readable mid-dodge.
- Charge state of both arms, and cooldowns.
- Directional arrows for incoming threats whose aim cone contains you, with
  escalating intensity.
- Missile lock warnings and missile direction (precise — dodging is the entire
  interaction).
- `SWORD NEARBY, ON THIS SIDE` proximity warning.
- Bomb location and carrier highlight, through geometry.
- Enemy teleport-home notifications.
- Speed readout (see §17).
- Scoreboard, optionally including enemy loadouts.

### 15.4 Customization and integrity

- The HUD is **fully customizable** by the player.
- **Server owners choose:** force the default UI, or allow any UI. This resolves
  the competitive-integrity question socially rather than technically, the way
  Quake and WoW handled the same problem. Competitive servers force default;
  casual servers allow anything.
- **The API exposes sanctioned fields only.** This is the actual security
  boundary and it must be designed before the HUD is built. Even in permissive
  mode, if the API can read enemy positions, someone writes a wallhack HUD.
  Define the read-only surface up front; everything else is invisible to the API.

Implementation shape: the HUD is a swappable Godot scene reading from a
read-only game-state singleton that exposes precisely the sanctioned fields.

---

## 16. Audio

Loud, directional, and physical.

- Railgun charge is the signature sound — audible, directional, distinct per arm
  phase so dual-rail staggering is readable by ear.
- Canister ejection on fire.
- Sword lunge impact.
- Wallrun contact and dismount, scaling with speed.
- Teleport-home is audible to enemies.

Audio is not the primary information channel (the HUD is), but it should be rich
enough that a player who has learned the sounds can act on them before the UI
resolves.

---

## 17. Feel & Feedback

**This section is not polish. In this design it is the primary reward system.**

There is no progression, no stats-based retention, no cosmetics economy, and only
only a handful of scoring events per ten-minute match. **Skill expression and moment-to-
moment satisfaction are what keep people playing.** That places the entire
retention load on feel.

Budget real time for:

- **Canister ejection** on every railgun shot. Physical, satisfying, tumbling.
  This was in the design from the first sketch and it is more load-bearing than
  it looks.
- **Hit confirmation** — unambiguous, immediate, distinct for body vs. head.
- **Lunge connect** — the sword landing must feel enormous.
- **Wallrun chain feedback** — a speed readout that climbs, escalating audio,
  camera and FOV response. A well-executed chain should feel better than any
  scoreboard number the game could offer.
- **Cannon launch** — the moment of being fired back into the fight should be a
  highlight, not a transition.
- **Shield break** — you spent a one-per-life resource; it should register.

---

## 18. Art Direction

- **Simple, readable, cheerful** — Astroneer as the touchstone.
- **Does not take itself seriously visually. Is mechanically deadly serious.**
- Cylindrical platforms as the signature form.
- Readability is the hard constraint: players are small, fast, often airborne,
  and frequently against skybox. Silhouettes and team colors must resolve at
  distance and at speed.
- Because HP is uniform and there are no classes, arm weapons are the main
  visual differentiator between players — worth making them legible at range even
  though the game doesn't strictly require it.

---

## 19. Servers, Modding & SDK

### 19.1 Architecture

- **Private servers with a server browser.** No centralized matchmaking. This is
  the correct architecture for a solo developer — zero hosting cost — and it fits
  the lineage (Quake, Tribes, Diabotical).
- Dedicated server binary shipped alongside the client.

### 19.2 Server owner controls

- Force default UI, or allow custom UIs.
- Custom maps, including deliberately specialized ones (rail-only servers with
  rail-optimized geometry, etc.).
- Standard rule tuning.

### 19.3 SDK scope

**Currently scoped to UI customization only.**

- Free. It is not a revenue source; its return is community, mods, and
  credibility. Charging for it would shrink the audience for the thing whose
  entire value is having an audience.
- Sanctioned read-only field access (§15.4).

**Deferred:** the AI-vs-AI / bot-upload concept (Screeps-style) is punted for now.
If revisited, the constraints established are:
- Server-side only. Never a local client API — that is a documented cheat toolkit.
- Ship it inside the dedicated server binary so hosts run the compute.
- An FPS needs decisions at tens of hertz, which is orders of magnitude more
  expensive than Screeps' slow tick. The viable shape is an **intent-level API**
  (bots issue goals at ~5-10Hz, the engine executes movement and aiming), not
  raw per-frame input.

---

## 20. Technical Plan

### 20.1 Engine

**Godot 4.**

### 20.2 Networking

- Authoritative server, client-side prediction for movement, server-side rewind
  (lag compensation) for hitscan.
- Godot 4's built-in multiplayer does not provide lag compensation or rewind —
  this must be written.
- **The charge-up railgun is unusually netcode-friendly.** A one-second telegraph
  means peeker's advantage barely exists and rewind disagreements are far more
  forgiving than instant hitscan would be. The combat design accidentally solved
  the hardest networking problem. Do not trade this away.
- Target 12 players.

**Architecture decisions (2026-09-09, with the roadmap gates passed):**

- **Per-match server processes.** The lobby stays matchmaker-only; it spawns a
  child authoritative-server process per match. Isolation and crash
  containment over single-process simplicity.
- **The LAN listen-server converts to server-auth** — the host's process runs
  the authoritative sim and the host plays as a zero-latency client. One
  netcode path everywhere; the legacy client-auth LAN-trust path is retired
  with it. Offline solo stays locally simulated and untouched.
- **Sword lunges use the same server-side rewind as rail hitscan.**
  Consistent attacker feel; the proximity warning remains the victim's
  mitigation (§22 risk 3).
- **Staging: N1** server-auth 1v1 parity (prediction + reconciliation) →
  **N2** server-side rewind for hitscan + lunge → *playtest gate: duels must
  feel like the prototype did* → **N3** scale to 12 (unlocks the 6v6
  prototype and §22 risk 1 measurement).

### 20.3 Character controller

Godot's `CharacterBody3D` is a starting point, but a custom kinematic controller
is likely necessary for the speeds and the wallrun behavior.

---

## 21. Monetization

**Free to play.** The SDK is free. There is no cosmetics economy planned and no
progression system.

This is explicitly **not** structured as a business. Retention is skill
expression and satisfaction (§17), not stats, unlocks, or a battle pass.

---

## 22. Known Risks

**1. Defense may be too strongly advantaged.** *(new, from the bomb-carry direction)*
The whole point of carrying into the enemy base is that defense gets the edge --
they respawn on the objective and the bomb comes to them. The risk is overshoot.
Teleport jamming (section 6.3), extended attacker cannon range (section 6.1), and
the bomb respawn offset are the three counterweights. If a full push still cannot
score against a competent defense, the mode does not work. "Scoring is impossible"
is a much worse failure than the "scoring is automatic" problem this direction was
adopted to fix, so this is the first thing to measure once 6v6 is playable.

**2. Curved-surface wallrun in Godot.**
Wallrunning on cylinders is fiddly with `CharacterBody3D`, and it is load-bearing
for both the art direction and the fuel economy. Prototype this specific
interaction before committing to the cylindrical platform aesthetic.

**3. Networked melee.** *(highest engineering risk)*
A one-shot kill, delivered by a long lunge, at very high speed, with client
prediction, over the internet. This is the problem Halo and Titanfall fought and
never fully won, and ours is harder -- longer lunge, higher speeds, no health
buffer to absorb a bad call. **"I hit him and died" will be a permanent bug
report.** The `SWORD NEARBY` warning is a partial mitigation. Test networked
lunge-melee against a real client at ~60ms latency early, because if it feels bad
there, it changes the weapon design -- and the sword is the bomb carrier's kit.

**4. Everything "once per life" is really "once per trip home."**
Teleport home is instant, free, heals, refreshes loadout, and refreshes the
non-recharging gunshield. The real unit of accounting is a round trip, not a
life. Teleport jamming complicates this further: the defending team's refresh rate
drops to zero at exactly the moment they are under most pressure, which is a large
and untested swing. Every per-life cooldown must be tuned against the true refresh
period, jammed and unjammed.

**5. Attacker cannon range overlaps defender launch zones.**
The extended range for the carrying team puts attackers in the same airspace the
defenders launch into, creating spawn pressure on a team that is already losing
the objective fight. Needs either a hard stop short of the launch zone or
geometric protection on defender exits.

**6. Swinginess at low score counts.**
A small number of scores per match, plus enormous kill value, plus a push that
takes a coordinated team, means one lost teamfight can decide a lot. Ranked's
first-to-3 format is the mitigation. The deepest-incursion tiebreak reduces the
sting by making close, scoreless games resolvable rather than empty.

**7. Telegraph saturation in 6v6.**
Mitigated by aim-cone-only warnings (section 15.2). Verify this actually holds with
twelve players before building more UI.

**8. Single map cannot deliver "all archetypes viable."**
See section 14.7. This is a scope commitment, not a tuning problem.

**9. 1v1 and 6v6 will feel like different games.**
Same systems, wildly different texture -- 1v1 is a legible duel, 6v6 is a mosh
pit where six telegraphs happen at once. Tuning for one can break the other.
6v6 wins every argument.

## 23. Open Questions

**Objective / pacing** *(the live set, following the bomb-carry inversion)*

- **Teleport jamming** -- confirm the rule. Is it a full block while an enemy
  carries the bomb toward your base, or a cooldown, or a partial (teleport allowed
  but no heal / no loadout swap)? Full block is proposed; it is the cleanest and
  the most dramatic, and also the most aggressive.
- **Plant interruption.** Does killing the planter reset plant progress entirely,
  or does partial progress persist? Reset is simpler and more dramatic.
- **Plant duration.** Long enough to be a real last stand, short enough that a
  cleared base is a genuine win.
- **Attacker cannon extension** -- how much further, and does it stop short of the
  defenders' launch zone?
- Final score target for casual. Ranked is Bo3 / first-to-3.
- Does the bomb ever return to center on its own, or truly never?
- Deepest-incursion tiebreak: what happens on an exact tie? (Draw is fine.)

**Combat**

- Exact charge time, and the tuned "generous" gap between staggered dual-rail
  shots.
- Threat-warning filtering in 6v6: the current plan is to warn on *every*
  charge (see 15.2); if playtests show that's ambient noise, what filter
  replaces the cut aim-crush cone?
- Does the gunshield block missiles?
- Missile upgrade: once per life, or a long cooldown? (Note this interacts with
  teleport jamming -- a jammed defender cannot refresh it.)

**Movement**

- Airfuel capacity in dashes, and the size of a wallrun dismount refill.
- Duration of the ramp-persistence grace window between wallruns.
- Terminal velocity value.
- Sword lunge cooldown, and its Airfuel cost relative to a dash.

**Upgrades**

- **The upgrade list needs rebuilding** (section 10.1). What fills it out now that
  invisibility, gravity, and the shoulder mount have all been absorbed or cut?
  Note that the sudden-death centerline drops are also gone, so on-map bonus
  upgrades no longer have a home unless deliberately re-added to the main mode.
- Do map-dropped bonus upgrades (if kept) stack with your chosen one, or replace it?

**Map**

- Corridor length (blocked on movement prototype).
- Density profile and target sight-break interval.
- Base geometry: how defensible should the plant site be? This is the single
  biggest lever on whether pushes can succeed.
- Cannon aiming arc width and number of exits.

**Modes**

- ~~1v1 duel win condition~~ — answered 12.2: first to 5 kills (prototype
  decision, 2026-09-09).

## 24. Prototype Roadmap

The design is at the point where the remaining questions are numbers, and numbers
come from playing, not from more argument.

**Step 1 — Movement alone.**
Gray box corridor. One player. No weapons, no opponent.
Wallrun, dismount fuel + speed grant, ramp persistence across gaps, air dash,
down dash, terminal velocity, Airfuel meter.

*Answers:* does the chained-short-runs feel emerge from the dismount reward? Is
curved-surface wallrun viable in Godot? How far apart can platforms be before
flow breaks? **How long should the corridor actually be?**

**Step 2 — Railgun against a stationary target.**
Charge, freeze/trajectory-lock, auto-fire, canister ejection, hit
confirmation.

*Answers:* does the charge feel good to commit to?

**Step 3 — Duel feedback + LAN playtesting.**
The real test. Polish the HUD information layer — enemy charge warning,
damage-taken feedback, sword proximity warning, kill/round presentation — so
LAN duels carry the full information game, then answer the question in real
1v1s. Charge → tell → dodge, in both directions. The playtesting instrument
is the Dockerized lobby server (`docker/` — join, pick a username, challenge,
first-to-5): it makes remote 1v1s cheap, but it is still the LAN-trust
throwaway netcode, NOT §20.2.
(This step was originally "one bot that shoots back" — replaced, see
Appendix A: LAN multiplayer arrived early and a real human is the better
instrument.)

*Answers:* **is the charge-freeze-dodge rhythm a fun conversation or a coinflip?**
Everything downstream depends on this.

**Answered 2026-09-09: a fair conversation.** Remote 1v1s on the lobby server
play well from both seats; the HUD information layer does its job (exact
presentation and warning filtering stay tunable, §23). The §23 combat/movement
numbers are good enough to proceed and stay open as tuning, not blockers.

**Step 4 — Networked lunge-melee at ~60ms.**
Two real clients. Sword only.

*Answers:* is melee salvageable at these speeds over a network? Pulled early
deliberately — see §22. A prototype-tier networked sword already exists, so
this folds into the same LAN playtesting sessions as Step 3.

**Answered 2026-09-09: yes.** Lunge melee held up at real latency in the same
remote duels; no sword-only session format was needed. §22 risk 3 is
downgraded from "may change the weapon design" to a netcode-quality concern
for the §20.2 implementation.

Everything else waits. *(All four gates passed 2026-09-09. Next milestone,
chosen the same day: the §20.2 netcode — authoritative server, client
prediction, server-side rewind — staged to 1v1 parity first.)*

---

## Appendix A: Cut Ideas

Recorded with reasons, so they don't get re-proposed.

**Airfuel refills on death.** Made suicide an optimal resource decision and
bypassed the movement system with a keybind. Replaced by wallrun-only.

**Airfuel refills on kill.** Snowballed — the player winning fights got the
mobility to keep winning. Replaced by wallrun-only.

**Invisibility upgrade.** Miserable to play against alongside a one-shot sword,
and as a contested upgrade it rewarded the team already winning. Cut entirely.

**Contested on-map upgrade points.** Standing still is the worst possible verb
in this game, the shield made them uncontestable, and they snowballed. Replaced
by loadout-selected upgrades.

**Personal gravity (held state).** Replaced by a universal down dash. Same jobs,
instantly legible, one ability instead of a state to tune and explain.

**The Tagger (tag-then-missile weapon).** As a "difficult to dodge one-shot" it
was just a railgun that didn't require aim, which undercut the rail's skill
expression. The missile-dodging fantasy survives as an upgrade (§10.1). Cutting
it also left a clean three-loadout triangle.

**Shoulder mount as a distinct weapon class.** Became hard to read once it needed
its own balance profile. Replaced by two symmetric arm mounts.

**Weapon-linked HP / classes.** Made incoherent by two-arm loadouts, and it
imposed a hard silhouette-readability constraint. Replaced by uniform HP.

**Partial railgun charge / early release.** Rejected as insufficiently committal.
Note that the feint layer it would have provided arrived anyway, in a fully
committal form, through staggered dual-rail timing (§7.1).

**Progressive aim crush.** Degrading the shooter's turn rate as the charge
built felt bad to the shooter — like fighting the input device, not playing a
mechanic. Commitment already comes from the freeze; the dodge stays viable
because the shooter must track a very quick dash that can go in any of 8
directions, and tracking that dash is the skill check. Cutting it also cost
the aim-cone warning filter (§15.2), now replaced by warn-on-every-charge.

**Step 3 bot opponent.** The prototype roadmap's "one bot that shoots back"
was replaced by LAN 1v1 playtesting: working LAN multiplayer arrived early, a
real human answers the charge→tell→dodge question with better signal, and bot
AI quality would confound the feel test (a coinflip result could be the design
failing or just bad dodge heuristics). A bot may still return later as an
always-available *practice* opponent — that's an availability tool, not the
validity test, and it shouldn't be re-proposed as the latter.

**Tanky bomb carrier.** Rejected in favor of fast-and-fragile. The intended
fantasy is a carrier dodging through cover with a team playing around them.

**Multiple objectives / per-base flags.** Replaced by a single neutral object,
which lets 1v1 and 6v6 share rules and gives the map a clean center-and-two-ends
structure.

**Carry-it-home CTF (the original objective direction).** The neutral object was
originally carried from midfield back to your *own* base. Abandoned because the
geometry made the run trivial: your teleport home put your team at the
destination ahead of the carrier, while the defenders' teleport sent them the
wrong way, so only living chasers could contest a run. Winning the midfield fight
made the score nearly automatic, the outer quarters of the map were pure travel,
and the match had only one real phase. Inverting to carry-into-enemy-base
produced three phases (fight / push / breach), used the whole map, and turned the
neutral object into a two-way ratchet where a defensive pickup becomes an instant
counterattack. The cost of the inversion is that teleport home stopped being
self-balancing and required jamming (section 6.3).

**Teleport-home cooldown.** Cut, then partially reinstated. Under the original
carry-it-home objective it was unnecessary, because teleport sent you backward and
was anti-useful for chasing. The bomb-carry inversion destroyed that reasoning and
the constraint came back as **jamming** rather than a cooldown -- blocked only
while an enemy carries the bomb toward your base. Recorded here as a caution: this
constraint is load-bearing and should not be re-cut without re-checking the
objective's direction of travel.

**Team deathmatch as tie resolution.** Two disciplined teams would simply hold
their ends. Briefly replaced by shrinking tick-damage regions forcing them to the
centre, then cut entirely in favour of the **deepest-incursion tiebreak**
(section 12.4), which needs no new ruleset, no shrinking play area and no bait
pickups, and which doubles as an anti-turtle mechanism during normal play.

**Paid SDK.** It was never going to be meaningful revenue, and charging shrinks
the audience for the thing whose value is having an audience.

**Bot-upload / AI-vs-AI (Screeps model).** Not cut, deferred. Constraints
recorded in §19.3.

---

## Appendix B: Tuning Variables

The full list of numbers that need values, gathered for convenience.

**Movement**
- Base run speed
- Gravity scale
- Terminal velocity
- Air dash: cost, distance, cooldown
- Down dash: cost, distance
- Double jump / air strafe: cost, strength
- Wallrun: max duration, speed accumulation curve
- Wallrun dismount: fuel granted, speed boost, both scaled to wall speed
- Ramp persistence: grace window duration, decay rate
- Airfuel: max capacity

**Combat**
- Railgun: charge time, damage (body/head)
- Dual rail: minimum enforced gap between shots
- Sword: lunge distance, lunge fuel cost, lunge cooldown per arm
- Sword warning: proximity radius
- Missile: lock time, missile speed, turn rate, cooldown/charges
- Gunshield: movement penalty, deploy/stow time

**Objective**
- Bomb carrier dash cooldown
- Bomb respawn offset toward trailing team (per score)
- Cannon range (baseline, and extended for the team carrying the bomb)
- Plant duration
- Plant interrupt behaviour (reset vs. persist)
- Teleport jamming trigger radius / condition
- Score targets: casual, ranked

**Map**
- Corridor length *(blocked on Step 1 prototype)*
- Sight-break interval
- Max distance from any point to a wallrunnable surface
- Vertical layer count and spacing
- Cannon aim arc, exit count

**Timing**
- Match length (10 min)
- Mercy rule threshold
- Deepest-incursion high-water mark: sample rate and display granularity
