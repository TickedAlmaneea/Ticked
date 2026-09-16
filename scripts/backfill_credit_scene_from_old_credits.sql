-- =====================================================================
-- Recover the credits-scene answer already sitting in `credits_start_min`.
--
-- Run this ONCE, AFTER add_credit_scene_to_films.sql, in the Supabase SQL
-- Editor. Costs nothing — no Gemini calls, no network. It only reads two
-- columns you already have.
--
-- Why this works: before the split, the app folded `has_credits_scene`
-- into `credits_start_min` (see GeminiApi.readAnswer as it was):
--
--     has_credits_scene = true   -> a real minute, always < duration_min
--     has_credits_scene = false  -> duration_min exactly
--
-- So the old column is not ambiguous in the direction that matters. A row
-- with credits_start_min < duration_min is a film Gemini positively said
-- has a scene, and that is exactly the set we want lit up — Spider-Man
-- among them. Backfilling it avoids re-asking Gemini for films it has
-- already answered about.
--
-- The one thing we cannot recover is WHERE in the credits the scene sits.
-- Old rows only kept the credits start, so that is what the scene minute
-- becomes: the terracotta span then covers the whole credits run, which
-- reads as "stay through the credits" rather than "stay until 1h58m".
-- Conservative in the right direction — it never tells someone to leave
-- before a scene they should have stayed for.
--
-- Rows where credits_start_min = duration_min become the "asked, no
-- scene" sentinel, so they are never re-asked on this account.
--
-- Rows never asked at all (breaks_checked_at is null) are deliberately
-- left NULL — those still go to Gemini on first open, and get a precise
-- scene minute rather than this approximation.
-- =====================================================================

update films
set credit_scene_start_min = case
      -- Old code only wrote a minute below the runtime when Gemini said
      -- the film has a scene. Best available position: the credits start.
      when credits_start_min < duration_min then credits_start_min
      -- The old "no scene" value, carried over as the new sentinel.
      else duration_min
    end
where breaks_checked_at is not null      -- asked at least once
  and credit_scene_start_min is null     -- not already migrated
  and credits_start_min is not null
  and duration_min is not null;

-- Verify — Spider-Man and anything else with a scene should now show a
-- credit_scene_start_min below its runtime:
--
--   select title, duration_min, credits_start_min, credit_scene_start_min,
--          case
--            when credit_scene_start_min is null then 'never asked'
--            when credit_scene_start_min >= duration_min then 'no scene'
--            else 'HAS SCENE'
--          end as verdict
--   from films
--   where breaks_checked_at is not null
--   order by verdict, title;
