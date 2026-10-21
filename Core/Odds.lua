-- Bonus Roll Helper: odds of a Voidcore roll.
--
-- A Voidcore awards one random item from your loot spec's pool, minus what
-- you already won from it on that difficulty.  Every remaining item is equally
-- likely, so each outcome's chance is simply count / remaining.
local _, BRH = ...

local Odds = {}
BRH.Odds = Odds

-- Verdict thresholds on the chance of a wishlist item.
local GREAT_WISH = 0.5
local GREAT_MAX_AVOID = 0.1
local GOOD_WISH = 0.25

Odds.VERDICTS = {
    great = { label = "Great roll", color = { 0.30, 0.90, 0.45 } },
    good = { label = "Good roll", color = { 0.55, 0.85, 0.35 } },
    meh = { label = "Long shot", color = { 1.00, 0.75, 0.25 } },
    bad = { label = "Risky", color = { 0.95, 0.35, 0.30 } },
    none = { label = "Nothing wanted", color = { 0.60, 0.60, 0.66 } },
    empty = { label = "No items", color = { 0.60, 0.60, 0.66 } }
}

local function Verdict(result)
    if result.remaining == 0 then
        return "empty"
    end
    if result.wish == 0 then
        return result.avoid > 0 and "bad" or "none"
    end
    local wish, avoid = result.pWish, result.pAvoid
    if wish >= GREAT_WISH and avoid <= GREAT_MAX_AVOID then
        return "great"
    elseif wish >= GOOD_WISH and avoid < wish then
        return "good"
    elseif wish > avoid then
        return "meh"
    end
    return "bad"
end

-- Returns nil while the pool is loading, otherwise:
-- {
--   total, remaining, rolled     – pool size, items still in it, items already won
--   wish, avoid, dupe, other     – remaining items by category (disjoint)
--   pWish, pAvoid, pDupe, pOther – chance of each category on one roll
--   expectedRolls                – average rolls until a wishlist item (nil if none)
--   refilled                     – every item was won, so the next roll uses the full pool
--   verdict                      – key into Odds.VERDICTS
-- }
function Odds.Compute(source, bucket, specID)
    local pool = BRH.Pool.GetPool(source, bucket, specID)
    if not pool then
        return nil
    end
    local rolled = BRH.History.GetRolledSet(source, bucket)

    local rolledCount = 0
    for _, item in ipairs(pool) do
        if rolled[item.itemID] then
            rolledCount = rolledCount + 1
        end
    end
    -- An exhausted pool refills, so the next roll is from all of it again.
    local refilled = #pool > 0 and rolledCount == #pool

    local result = {
        total = #pool,
        rolled = refilled and 0 or rolledCount,
        remaining = 0,
        wish = 0,
        avoid = 0,
        dupe = 0,
        other = 0,
        refilled = refilled
    }
    for _, item in ipairs(pool) do
        if refilled or not rolled[item.itemID] then
            result.remaining = result.remaining + 1
            local mark = BRH.History.GetMark(item.itemID)
            if mark == "wish" then
                result.wish = result.wish + 1
            elseif mark == "avoid" then
                result.avoid = result.avoid + 1
            elseif BRH.History.IsLooted(item.itemID) then
                result.dupe = result.dupe + 1
            else
                result.other = result.other + 1
            end
        end
    end

    local remaining = result.remaining
    result.pWish = remaining > 0 and result.wish / remaining or 0
    result.pAvoid = remaining > 0 and result.avoid / remaining or 0
    result.pDupe = remaining > 0 and result.dupe / remaining or 0
    result.pOther = remaining > 0 and result.other / remaining or 0
    -- Drawing without replacement: expected draws to the first of W wanted
    -- items among N is (N + 1) / (W + 1).
    if result.wish > 0 then
        result.expectedRolls = (remaining + 1) / (result.wish + 1)
    end
    result.verdict = Verdict(result)
    return result
end

-- Compares every spec of the class for this source.
-- Returns best { spec, odds } (highest wishlist chance, then lowest avoid
-- chance) and loading = true if some spec's pool isn't read yet.
function Odds.BestSpec(source, bucket)
    local best, loading
    for _, spec in ipairs(BRH.GetClassSpecs()) do
        local odds = Odds.Compute(source, bucket, spec.specID)
        if not odds then
            loading = true
        elseif odds.wish > 0 then
            if not best or odds.pWish > best.odds.pWish or
                (odds.pWish == best.odds.pWish and odds.pAvoid < best.odds.pAvoid) then
                best = {
                    spec = spec,
                    odds = odds
                }
            end
        end
    end
    return best, loading
end
