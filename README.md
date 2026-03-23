# 📚 BookWorm — Reading League Smart Contract

A Clarity smart contract on the Stacks blockchain that gamifies reading. Readers join a league, set reading quests with page goals and deadlines, log progress, earn wisdom points, level up through scholar tiers, collect honors, and claim token rewards from a shared vault.

---

## Table of Contents

- [Overview](#overview)
- [Data Structures](#data-structures)
- [Public Functions](#public-functions)
- [Read-Only Functions](#read-only-functions)
- [Administrative Functions](#administrative-functions)
- [Error Codes](#error-codes)
- [Scholar Tiers](#scholar-tiers)
- [Reward Calculation](#reward-calculation)
- [Usage Example](#usage-example)

---

## Overview

| Property | Value |
|---|---|
| Language | Clarity 2 |
| Network | Stacks (Bitcoin L2) |
| Time tracking | `burn-block-height` |
| Access control | Single library keeper (admin) |

---

## Data Structures

### `book-readers` map

Stores each reader's profile, keyed by their principal address.

| Field | Type | Description |
|---|---|---|
| `wisdom-points` | `uint` | Cumulative points earned from reading |
| `reading-sessions` | `uint` | Total number of progress submissions |
| `scholar-tier` | `uint` | Current tier level, derived from wisdom points |
| `last-session-time` | `uint` | Block height of the last reading session |
| `wisdom-tokens` | `uint` | Redeemable tokens claimed from completed quests |
| `current-quests` | `uint` | Total quests created (also used as the latest quest ID) |

### `reading-quests` map

Stores individual quests, keyed by `{reader, quest-number}`.

| Field | Type | Description |
|---|---|---|
| `pages-target` | `uint` | Number of pages required to complete the quest |
| `pages-completed` | `uint` | Pages logged so far |
| `quest-timeout` | `uint` | Deadline expressed as a future `burn-block-height` |
| `quest-finished` | `bool` | Whether the page target has been met |
| `knowledge-reward` | `uint` | Tokens awarded upon quest completion |
| `book-genre` | `string-ascii 20` | Genre label (e.g. `"fiction"`, `"non-fiction"`) |

### `scholar-honors` map

A list of up to 10 honor titles (badges) earned by a reader. Each honor is a string such as `"Finished fiction"`.

---

## Public Functions

### `join-reading-league`

Registers the caller as a new reader. Fails if the caller is already enrolled.

```clarity
(join-reading-league)
```

**Returns:** `(ok true)`

---

### `begin-reading-quest`

Creates a new reading quest for the caller.

```clarity
(begin-reading-quest (page-objective uint) (time-limit uint) (genre-type (string-ascii 20)))
```

| Parameter | Description |
|---|---|
| `page-objective` | Pages to read — must be greater than `0` |
| `time-limit` | Deadline as a **future block height** (e.g. `burn-block-height + 1000`) |
| `genre-type` | Genre string, max 20 characters |

**Returns:** `(ok quest-number)` — the ID of the newly created quest.

> ⚠️ **Block height, not Unix time.** Pass a future `burn-block-height` value as the deadline. Approximately 1 Bitcoin block ≈ 10 minutes, so 144 blocks ≈ 1 day.

---

### `submit-reading-progress`

Logs pages read against an active quest. Automatically marks the quest complete if the page target is reached and awards an honor badge.

```clarity
(submit-reading-progress (quest-number uint) (pages-read uint))
```

| Parameter | Description |
|---|---|
| `quest-number` | ID of the quest to update |
| `pages-read` | Pages read in this session (must be `> 0`) |

**Returns:**
```clarity
(ok { pages: uint, completed: bool, wisdom: uint })
```

| Field | Description |
|---|---|
| `pages` | Cumulative pages logged for this quest |
| `completed` | Whether the quest target has been reached |
| `wisdom` | Reader's new total wisdom points |

**Side effects on completion:** A scholar honor titled `"Finished <genre>"` is added to the reader's honors list.

---

### `collect-knowledge-reward`

Claims the token reward for a completed quest. Transfers tokens from the knowledge vault to the reader's balance.

```clarity
(collect-knowledge-reward (quest-number uint))
```

**Requires:**
- Quest must be marked `quest-finished: true`
- The knowledge vault must hold enough tokens to cover the reward

**Returns:** `(ok reward-amount)`

---

## Read-Only Functions

### `fetch-reader-profile`

Returns the full profile map for a reader, or `none` if not enrolled.

```clarity
(fetch-reader-profile (reader principal))
```

---

### `fetch-quest-details`

Returns details for a specific quest.

```clarity
(fetch-quest-details (reader principal) (quest-number uint))
```

---

### `fetch-reader-honors`

Returns the list of honor badges earned by a reader.

```clarity
(fetch-reader-honors (reader principal))
```

---

### `fetch-league-statistics`

Returns global stats for the reading league.

```clarity
(fetch-league-statistics)
;; => { total-readers: uint, vault-balance: uint }
```

---

## Administrative Functions

These functions are restricted to the `library-keeper` (contract deployer by default).

### `replenish-knowledge-vault`

Adds tokens to the knowledge vault used to fund quest rewards.

```clarity
(replenish-knowledge-vault (token-sum uint))
```

---

### `designate-new-keeper`

Transfers admin rights to a new principal. The successor cannot be the current keeper.

```clarity
(designate-new-keeper (successor principal))
```

---

## Error Codes

| Constant | Code | Trigger |
|---|---|---|
| `ERR-UNAUTHORIZED-ACCESS` | `u100` | Caller is not the library keeper |
| `ERR-READER-DUPLICATE` | `u101` | Reader already enrolled |
| `ERR-READER-ABSENT` | `u102` | Reader not found |
| `ERR-OBJECTIVE-ERROR` | `u103` | Invalid page target, deadline, or quest state |
| `ERR-VAULT-SHORTAGE` | `u104` | Insufficient tokens in the knowledge vault |
| `ERR-AMOUNT-ERROR` | `u105` | Amount parameter is zero or invalid |
| `ERR-SESSION-ERROR` | `u106` | Pages-read value is zero |
| `ERR-QUEST-ERROR` | `u107` | Quest number out of range or not found |

---

## Scholar Tiers

A reader's tier is automatically recalculated each time progress is submitted, using:

```
tier = 1 + floor(wisdom_points / 1000)
```

| Tier | Wisdom Points Required |
|---|---|
| 1 | 0 — 999 |
| 2 | 1,000 — 1,999 |
| 3 | 2,000 — 2,999 |
| … | … |

---

## Reward Calculation

**Wisdom points** are awarded per session:
```
wisdom_gain = pages_read × 10
```

**Quest knowledge reward** is fixed at quest creation time:
```
knowledge_reward = floor(pages_target / 100) × 100
```

For example, a 250-page quest yields a reward of `200` tokens. Ensure the vault is funded before readers attempt to claim.

---

## Usage Example

```clarity
;; 1. Admin funds the vault
(contract-call? .bookWorm replenish-knowledge-vault u5000)

;; 2. Reader enrolls
(contract-call? .bookWorm join-reading-league)

;; 3. Reader starts a quest: 200 pages, deadline in ~7 days (~1008 blocks), genre "mystery"
(contract-call? .bookWorm begin-reading-quest u200 (+ burn-block-height u1008) "mystery")

;; 4. Reader logs progress over multiple sessions
(contract-call? .bookWorm submit-reading-progress u1 u80)
(contract-call? .bookWorm submit-reading-progress u1 u80)
(contract-call? .bookWorm submit-reading-progress u1 u60) ;; quest completes here

;; 5. Reader claims their reward
(contract-call? .bookWorm collect-knowledge-reward u1)
```