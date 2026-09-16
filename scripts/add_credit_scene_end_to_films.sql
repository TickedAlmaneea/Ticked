-- =====================================================================
-- Give the credits scene an end as well as a start.
--
-- Run this ONCE in the Supabase SQL Editor, after
-- add_credit_scene_to_films.sql. Safe on a live project: it adds one
-- nullable column and touches no existing data.
--
-- Why: a credits scene is a short insert inside the credits, not the
-- whole tail of the film. The real shape is
--
--     ...film... | credits | SCENE | credits | end
--
-- but with only a start minute the app had to draw the scene from its
-- start all the way to the runtime, which says "everything from here on
-- is the scene" — wrong, and it hides the fact that there are still
-- several minutes of ordinary credits to sit through afterwards.
--
-- With both minutes the timeline draws the grey credits span across the
-- whole tail and paints the scene over just its own stretch, so the
-- credits show either side of it exactly as they run in the cinema.
--
-- Three states, the same shape credit_scene_start_min uses. A film with
-- no credits scene has BOTH columns pinned to duration_min:
--
--   NULL              never asked.
--   = duration_min    asked; no scene (or a scene running to the last
--                     frame). Nothing red is drawn.
--   < duration_min    the scene stops there and the credits resume.
--
-- NULL is never written by the app for a film it has asked about: null
-- means "not asked", so leaving it there would send that film back to
-- Gemini on every open.
-- =====================================================================

alter table films
  add column if not exists credit_scene_end_min integer;

comment on column films.credit_scene_end_min is
  'Minute (from first frame) the mid/post-credits scene ends. NULL = not known; the scene is then drawn to duration_min. Must be greater than credit_scene_start_min.';

-- Verify — films with a scene should get a bounded window, and the end
-- should sit at or before the runtime:
--
--   select title, duration_min, credits_start_min,
--          credit_scene_start_min, credit_scene_end_min
--   from films
--   where credit_scene_start_min is not null
--     and credit_scene_start_min < duration_min
--   order by title;
