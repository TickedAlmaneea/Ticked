-- =====================================================================
-- Split "when the credits roll" from "there is a scene in the credits".
--
-- Run this ONCE in the Supabase SQL Editor (your project > SQL Editor >
-- New query > paste this > Run). Safe on a live project: it adds one
-- nullable column and touches no existing data.
--
-- Why it's needed: the app was already asking Gemini `has_credits_scene`
-- (see GeminiApi.buildPrompt), but had nowhere to put the answer, so it
-- folded the boolean into `credits_start_min`:
--
--     credits_start_min = <real minute>  ->  there IS a credits scene
--     credits_start_min = duration_min   ->  there is NOT
--
-- That overload cost us the thing the column is named after. A film with
-- credits at 1h52m but no post-credits scene stored 120, not 112, so the
-- honest credits minute was thrown away for every film without a scene —
-- and the grey "Credits" span on the timeline silently meant "stay put",
-- which is not what its label said.
--
-- After this migration the two are separate:
--
--   credits_start_min       when the end credits begin. Informational —
--                           "the film is over, you can go". NULL = unknown.
--
--   credit_scene_start_min  when the mid/post-credits scene plays, which
--                           is the one that matters. Three states, the
--                           same two-state-encodes-three shape
--                           `breaks_checked_at` already uses:
--
--                             NULL              never asked (a row from
--                                               before this column, or a
--                                               film never opened). The
--                                               app re-asks Gemini the
--                                               next time it is opened.
--                             = duration_min    asked; no scene.
--                             < duration_min    asked; scene at that minute.
--
-- This script only adds the column; existing rows stay NULL. Most of them
-- do NOT need a Gemini re-ask to be filled in, though: the old overload is
-- recoverable, because `credits_start_min < duration_min` could only ever
-- have been written for a film Gemini said has a scene. Run
-- backfill_credit_scene_from_old_credits.sql straight after this one to
-- convert those for free; only films never asked about at all are left to
-- the lazy re-ask.
-- =====================================================================

alter table films
  add column if not exists credit_scene_start_min integer;

comment on column films.credit_scene_start_min is
  'Minute (from first frame) of the mid/post-credits scene. NULL = never asked; = duration_min = asked, no scene; < duration_min = scene at that minute.';

-- Verify — after opening a few films in the app, these should start
-- filling in, and the two columns should no longer move together:
--
--   select title, duration_min, credits_start_min, credit_scene_start_min
--   from films
--   where breaks_checked_at is not null
--   order by title;
