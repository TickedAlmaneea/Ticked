<div align="center">

<img src="assets/images/app_logo.png" alt="Ticked" width="140">

# Ticked

**A cinema companion for Riyadh.**

*Your ticket says 9:00. The film actually starts at 9:18. We timed it.*

[![Flutter](https://img.shields.io/badge/Flutter-3.13%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13%2B-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Supabase](https://img.shields.io/badge/Supabase-Postgres%20%2B%20Auth-3FCF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![Gemini](https://img.shields.io/badge/Gemini-vision%20%2B%20text-8E75B2?logo=googlegemini&logoColor=white)](https://ai.google.dev)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20Android-lightgrey)](#)

</div>

---

## 🎥 Demo

<div align="center">

<!-- ── DEMO VIDEO ───────────────────────────────────────────────────────
     Replace the line below with one of these once the video is up:

     YouTube — a thumbnail that links to the video (GitHub won't embed
     a player, so this is the standard pattern):
         [![Watch the demo](https://img.youtube.com/vi/VIDEO_ID/maxresdefault.jpg)](https://youtu.be/VIDEO_ID)

     Hosted on GitHub — drag an .mp4 (under 10 MB) into any issue or PR
     comment, copy the URL it generates, and paste it on its own line.
     GitHub renders that as an inline player:
         https://github.com/user-attachments/assets/XXXXXXXX

     Keep it under about 90 seconds: ticket photo ➜ real schedule ➜
     live session ➜ a break counting down.
─────────────────────────────────────────────────────────────────────── -->

**🎬 Demo video coming soon** — a ticket photographed, read, and turned into a live session in under a minute.

</div>

---

## 🎯 The problem

Every cinema ticket states a time that is not the time the film begins.

A ticket printed **9:00 PM** actually means seating at 9:00, advertisements until 9:18, the film from 9:18, and the credits at 11:12. Nobody knows when to arrive, nobody knows when it ends, and leaving your seat is a gamble.

Booking apps sell the ticket and stop being useful the moment you sit down. Film databases give the runtime but say nothing about the screening.

**Ticked is useful during the two hours every other cinema app ignores.**

---

## ✨ What it does

|  | Feature |
|---|---|
| 🎟️ | **Reads your ticket from a photo.** Gemini vision pulls the cinema, branch, film and time out of a creased thermal-paper ticket — every field lands editable, so a bad read is a two-tap correction, not a dead end. |
| ⏱️ | **Computes the real schedule.** True start, true end, and the ad-block breakdown, from timings measured at each chain by hand. |
| 📊 | **Runs a live session.** A colour-segmented timeline — ads, film, safe breaks, credits — advancing in real time, accurate through backgrounding and network loss. |
| 🚪 | **Tells you when it's safe to leave.** AI-generated safe windows, cached forever after the first person asks, with estimates labelled as estimates. |
| 🔒 | **Puts it on the Lock Screen.** A native iOS Live Activity in the Dynamic Island, updated every second. |
| 📈 | **Remembers.** History and a yearly recap: *"You have watched 6.2 hours of advertisements this year."* |

---

## ⚙️ How it works

### 🎬 The ad block — researched, not guessed

The gap between the printed showtime and the film starting is fixed, knowable, and published nowhere. So we studied it ourselves: attending screenings across Riyadh's five chains and timing the gap, repeatedly, until the numbers held.

Each chain gets two values — one for films under two hours, one for films over — because longer films run shorter ad blocks. The ad block belongs to the chain, not the building; every VOX runs the same reel. So it lives on `cinemas`, while locations live on `branches`.

That dataset is the product. It exists nowhere else, and it is why the app can tell you a real start time instead of a guess.

### 🎞️ The listings — scraped

There is no API for what is playing in Riyadh tonight. Python scrapers read each chain's own site, and a daily sync upserts films and showtimes into Supabase with the service-role key. The app only ever reads them.

Branches are the exception: they're hand-managed in Supabase rather than auto-upserted, because a chain's own branch naming drifts and silently duplicating a location is worse than typing thirty rows once.

### ⏸️ The safe breaks — asked once, then free forever

```
open a film
   │
   ├─ breaks cached? ──────────────► return them                    0 tokens
   ├─ "asked, found nothing" < 7d? ► "no safe breaks"               0 tokens
   └─ never asked ────────────────► Gemini ──► store ──► return
                                      ├─ strict pass: only if it knows the film
                                      └─ declined? estimate, and label it
```

Three details make this cheap and correct:

- **The first viewer pays; nobody after them does.** Breaks are cached against the film row and stamped with `breaks_checked_at`, so every later user opening that listing reads the table instead of the API.
- **Empty answers expire after 7 days; real answers never do.** A film's scenes don't move, but "Gemini didn't know this film" is a statement about the day it was asked — and stops being true as a film becomes better known.
- **The schedule never depends on it.** If Gemini is offline or out of quota, the Schedule Card says so calmly and everything else on screen is still correct.

---

## 🧰 Tech stack

| Layer | Choice |
|---|---|
| Framework | Flutter (Dart), iOS + Android |
| Backend | Supabase — Postgres, Auth, Row Level Security, Storage |
| AI | Google Gemini (`gemini-3.5-flash-lite`, falling back to `gemini-3.1-flash-lite`) |
| State | Plain `StatefulWidget` / `setState` |
| Live Activity | `live_activities` + `flutter_app_group_directory` + a Swift widget extension |
| Listings | Python scrapers, scheduled daily via `launchd` |

No TMDB, and no state-management package. Film metadata came from TMDB in an early design; it knows films, not screenings in Riyadh, so it was dropped for scraping. The session clock ended up owned by a single screen, so a state library would have been ceremony rather than architecture.

---

## Project structure

```
lib/
├── constants/      colours, typography, theme
├── data/           TickedRepository (the frozen contract) + SupabaseRepository
│                   ticket_ocr_service.dart — photo ➜ ParsedTicket
├── models/         Film, Branch, Cinema, Schedule, FilmBreak, Attendance, …
├── screens/
│   ├── auth/       sign in, sign up, confirm email, forgot / set password
│   ├── home/       now showing, starting soon
│   ├── cinemas/    per-chain browsing
│   ├── ticket/     upload and read a ticket photo
│   ├── schedule/   Schedule Card ➜ Live Session (one screen, two states)
│   ├── history/    attended screenings + yearly recap
│   ├── profile/    stats, avatar, display name
│   ├── settings/   notifications, sign out, delete account
│   └── about/      the team
├── services/       database.dart (all Supabase calls)
│                   gemini_api.dart, live_activity_service.dart
└── widgets/        segmented timeline, code input, carousels, …

scripts/            Python scrapers, daily sync, SQL schema and migrations
ios_live_activity_staging/
                    Swift widget extension + its Xcode setup checklist
```

The repository interface in `lib/data/ticked_repository.dart` was frozen on day 1 so both developers could work in parallel — one against a fake implementation, one building the real one. Swapping the fake for `SupabaseRepository` cost no screen a single line.

---

## 🚀 Getting started

### Prerequisites

- Flutter 3.13 or newer
- A [Supabase](https://supabase.com) project (free tier is enough)
- A [Google AI Studio](https://aistudio.google.com/app/apikey) key for Gemini (free tier is enough)

### 1. Clone and install

```bash
git clone https://github.com/TickedAlmaneea/Ticked.git
cd Ticked
flutter pub get
```

### 2. Configure keys

```bash
cp .env.example .env
```

Fill in:

```ini
SUPABASE_URL=https://<your-project>.supabase.co
SUPABASE_PUBLISHABLE_KEY=<your anon / publishable key>
GEMINI_API_KEY=<your Google AI Studio key>
```

`.env` is git-ignored. Never commit it, and never put the **service-role** key here — that belongs only in `scripts/.env`, where the app cannot reach it.

### 3. Set up the database

In the Supabase SQL Editor, run these **in order**:

| # | File | What it does |
|---|---|---|
| 1 | `scripts/schema.sql` | Reference and listing tables, RLS policies, and the seeded ad-block numbers |
| 2 | `scripts/add_credit_scene_to_films.sql` | Splits "credits roll" from "there's a post-credits scene" |
| 3 | `scripts/add_credit_scene_end_to_films.sql` | Gives that scene an end as well as a start |
| 4 | `scripts/add_delete_account_function.sql` | `delete_own_account()` — real account deletion |

> ⚠️ **`schema.sql` is ahead of the running app.** It provisions a separate `movies` table and keys `breaks` on `movie_id`; the app caches breaks against `films.film_id` and has no `movies` table. Reconciling the two is tracked in the roadmap — until then, treat the app's column names as authoritative and check `scripts/` for the migration that matches your project.

You also need a `profiles` table and an `on_auth_user_created` trigger that fills it from sign-up's `display_name`, plus a public `avatars` storage bucket for profile photos.

### 4. Configure Auth

In **Authentication → Providers → Email**: enable **Confirm email** and set **Email OTP Length** to `6`.

Both email flows deliver a code, not a link — a link redirects to the project's Site URL and, under PKCE, only works on the device that asked for it. A code works wherever the email is read. So edit both templates under **Authentication → Email Templates** to print `{{ .Token }}` rather than `{{ .ConfirmationURL }}`:

```html
<h2>Confirm your email address</h2>
<p>Your Ticked confirmation code is:</p>
<p style="font-size:28px;letter-spacing:6px;"><strong>{{ .Token }}</strong></p>
<p>Enter it in the app to finish signing up. It expires in one hour.</p>
```

If you configure custom SMTP, keep **Sender email** and **Username** identical — otherwise the provider rewrites the `From` header and mail arrives from the wrong address. Set **Minimum interval per user** to `60` to match the app's resend cooldown.

### 5. Run

```bash
flutter run
```

<details>
<summary>iOS Live Activity (optional)</summary>

<br>

The Lock Screen widget is a native Swift target and needs wiring in Xcode. See `ios_live_activity_staging/SETUP_CHECKLIST.md`. Until it's set up, every Live Activity call is a silent no-op — the session itself runs identically, it just doesn't appear on the Lock Screen. It does nothing on Android, which has no equivalent API.

</details>

---

## The scraping pipeline

```
vox_scraper.py  ──►  sync_to_supabase.py  ──►  Supabase  ──►  the app reads
(+ muvi, scene, reel, cinehouse)
```

Films are identified by `(source, source_slug)` and branches by `(source, source_code)`, so a re-scrape upserts instead of duplicating; showtimes dedupe on `(branch_id, source_booking_id)`.

Create `scripts/.env` with `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` — deliberately a **separate file** from the app's `.env`, so the app's key can never gain write access to listings. Then:

```bash
python scripts/vox_scraper.py          # scrape
python scripts/sync_to_supabase.py     # upsert
./scripts/setup_daily_scrape.sh        # schedule it daily (macOS launchd)
```

See [`scripts/README.md`](scripts/README.md) for the full pipeline.

---

## 🗄️ Database

Seven tables.

| Table | Holds | Users may write |
|---|---|---|
| `profiles` | Display name, avatar | Own row |
| `cinemas` | The researched ad-block minutes | No — seeded |
| `branches` | Locations, one per chain per mall | No — hand-managed |
| `films` | One row per chain's listing of a film, plus its cached credits and `breaks_checked_at` stamp | Listing fields: scraper only |
| `breaks` | Safe windows, keyed on `film_id` | Yes |
| `showtimes` | What's playing where and when | No — scraper only |
| `movies_seen` | Attendance history | Own rows |

Row Level Security is on for every table. `showtimes` has no insert policy for `authenticated` at all — it is written exclusively by the scraper's service-role key, which bypasses RLS. Signed-in users can write `breaks` and the cache columns on `films`, because break generation runs on the device (see the roadmap).

`films` carries four columns the scraper never touches — `credits_start_min`, `credit_scene_start_min`, `credit_scene_end_min` and `breaks_checked_at`. That last one is the whole cache: a non-null stamp with no `breaks` rows means *"asked Gemini, found nothing"*, which is what stops the same film being sent to the API over and over. Negative caching is the part of this pattern that's usually forgotten, and here it costs no extra column.

---

## 🧪 Testing

```bash
flutter test
flutter analyze
```

---

## What we're honest about

- **Break suggestions are AI-generated.** Ones reasoned from runtime and pacing rather than actual knowledge of a film are stored as `is_estimated` and labelled in the interface, never passed off as researched fact.
- **Ad timings are researched, not live-measured.** They don't improve with use, and if a chain changes its reel the number is stale until someone re-times it.
- **Riyadh only.** Five chains, one city. A global version would necessarily be guessing — scoping down is what makes the data true.

---

## 🗺️ Roadmap

- 📱 **App Store and Google Play release**
- 🔐 Move break generation server-side, behind a Supabase Edge Function
- 🧱 Reconcile `scripts/schema.sql` with the shipped schema (it still provisions a `movies` table the app does not use)
- 🏙️ More cities, once the fieldwork behind them is real
- 🔔 Break reminders as push notifications
- 🤖 An Android equivalent of the Live Activity

---

## 👥 The team

| | |
|---|---|
| **Abdullah Almaneea** · Junior CS Student | [LinkedIn](https://www.linkedin.com/in/abdullah-maneea-299376344/) |
| **Latifa Almaneea** · Senior SWE Student | [LinkedIn](https://www.linkedin.com/in/latifa-m-62b518322/) |

Ticked was the final project of a Flutter bootcamp, and is being prepared for the App Store.

<div align="center">
<br>
<sub><i>That eighteen minutes isn't from an API. There is no API.<br>We went to the cinemas and timed it ourselves.</i></sub>
</div>
