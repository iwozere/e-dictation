# e-dictation — Deployment Guide

Covers two environments: **local development** (Docker + Supabase CLI) and
**production** (Supabase Cloud + GitHub Actions + Vercel).

---

## Overview

```
Local dev                         Production
─────────────────────────         ─────────────────────────────────────
flutter run -d chrome             push to GitHub main
  └─ --dart-define vars             └─ GitHub Actions
supabase start (Docker)                 ├─ flutter build web
  └─ migrations auto-applied           └─ vercel deploy
supabase functions serve          Vercel  ←  https://<project>.vercel.app
  └─ --env-file .env.local        Supabase Cloud  ←  cblahvjmhaqkhhbsplnh
```

---

## Local Development

### Prerequisites

| Tool | Version | Install |
|---|---|---|
| Docker Desktop | latest | https://www.docker.com/products/docker-desktop |
| Flutter SDK | 3.44+ | https://docs.flutter.dev/get-started/install |
| Supabase CLI | latest | `npm install -g supabase` |
| Node.js | 18+ | https://nodejs.org |

### First-time setup

```bash
# 1. Install Flutter dependencies
flutter pub get

# 2. Start local Supabase (Docker must be running)
supabase start

# 3. Apply all database migrations
supabase migration up

# 4. (Optional) Serve the Edge Function locally
supabase functions serve on_dictation_save --env-file .env.local
```

**`.env.local`** (gitignored — create manually):
```
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_TTS_API_KEY=AIza...
SUPABASE_URL=http://localhost:54321
SUPABASE_SERVICE_ROLE_KEY=<local service role key from supabase start output>
```

### Running the app locally

Use `run_web.bat` (gitignored) or run directly:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://localhost:54321 \
  --dart-define=SUPABASE_ANON_KEY=<local anon key from supabase start output>
```

Local Supabase endpoints after `supabase start`:

| Service | URL |
|---|---|
| API / PostgREST | http://localhost:54321 |
| Studio (DB browser) | http://localhost:54323 |
| Auth | http://localhost:54321/auth/v1 |
| Storage | http://localhost:54321/storage/v1 |
| Inbucket (email) | http://localhost:54324 |

### Resetting local DB

```bash
supabase db reset    # drops and re-applies all migrations (wipes data)
supabase migration up  # applies only new migrations (preserves data)
```

---

## Production — Supabase Cloud

**Project ref:** `cblahvjmhaqkhhbsplnh`  
**Project URL:** `https://cblahvjmhaqkhhbsplnh.supabase.co`

### Link CLI to the cloud project

```bash
supabase login
supabase link --project-ref cblahvjmhaqkhhbsplnh
```

### Push database migrations

```bash
supabase db push
```

Run this whenever a new migration file is added to `supabase/migrations/`.

### Deploy the Edge Function

```bash
supabase functions deploy on_dictation_save
```

### Set Edge Function secrets

In **Supabase Dashboard → Edge Functions → on_dictation_save → Manage secrets**,
or via CLI:

```bash
supabase secrets set \
  ANTHROPIC_API_KEY=sk-ant-... \
  GOOGLE_TTS_API_KEY=AIza...
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are auto-injected — do not set them manually.

### Enable Anonymous Sign-In

**Supabase Dashboard → Authentication → Settings → Allow anonymous sign-ins: ON**

Required for students to open dictations without an account.

---

## Production — Flutter Web → Vercel

### How it works

Every push to `main` triggers `.github/workflows/deploy.yml`:

1. GitHub Actions checks out the code
2. Installs Flutter (cached between runs)
3. Runs `flutter analyze`
4. Builds `flutter build web --release` with secrets injected via `--dart-define`
5. Copies `vercel.json` into `build/web/`
6. Deploys `build/web/` to Vercel with `vercel deploy --prod`

Typical build time: **~3 minutes**.

### Required GitHub Secrets

Set at **github.com/iwozere/e-dictation → Settings → Secrets and variables → Actions**:

| Secret | Value | Where to get it |
|---|---|---|
| `VERCEL_TOKEN` | Personal access token | vercel.com/account/tokens |
| `VERCEL_ORG_ID` | Organisation ID | `cat .vercel/project.json` after `vercel link` |
| `VERCEL_PROJECT_ID` | Project ID | `cat .vercel/project.json` after `vercel link` |
| `SUPABASE_URL` | `https://cblahvjmhaqkhhbsplnh.supabase.co` | Supabase Dashboard → Project Settings → API |
| `SUPABASE_ANON_KEY` | anon/public key | Supabase Dashboard → Project Settings → API |

### One-time Vercel project setup

```bash
npm install -g vercel
vercel login          # sign in with GitHub
vercel                # creates project, run from repo root
cat .vercel/project.json   # copy orgId + projectId → GitHub secrets
```

### Triggering a deploy manually

```bash
git commit --allow-empty -m "Trigger deploy" && git push
```

Or re-run the workflow in the GitHub Actions UI.

### Production URL

After first successful deploy, Vercel assigns a permanent URL:
`https://e-dictation.vercel.app` (or a custom domain if configured).

---

## Supabase Storage — Audio files

TTS-generated MP3s are stored in the `dictations` bucket:

```
dictations/{dictation_id}/sentence_0.mp3
dictations/{dictation_id}/sentence_1.mp3
...
```

The bucket is public-read (audio plays without auth). Upload/delete requires the
service role key (Edge Function only).

### CORS (if browsers block audio requests)

Supabase Dashboard → Storage → Configuration → Add CORS rule:

```json
[{
  "origins": ["*"],
  "methods": ["GET"],
  "headers": ["Range"],
  "exposeHeaders": ["Content-Length", "Content-Range"]
}]
```

---

## Database Migrations

Migrations live in `supabase/migrations/` and are numbered sequentially:

| File | Description |
|---|---|
| `001_initial_schema.sql` | Core tables: profiles, classes, dictations, dictation_sentences, attempts |
| `002_rls_share_code_hardening.sql` | RLS policies for share-code-based student access |
| `003_tts_status.sql` | `tts_status` + `tts_error` columns on dictations for async TTS tracking |

**Adding a new migration:**

```bash
supabase migration new <description>   # creates 004_<description>.sql
# edit the file, then:
supabase migration up                   # apply locally
supabase db push                        # apply to production
```

---

## Environment Variables Summary

| Variable | Local | Production | Used by |
|---|---|---|---|
| `SUPABASE_URL` | `http://localhost:54321` | `https://cblahvjmhaqkhhbsplnh.supabase.co` | Flutter (dart-define) |
| `SUPABASE_ANON_KEY` | from `supabase start` output | Supabase Dashboard → API | Flutter (dart-define) |
| `ANTHROPIC_API_KEY` | `.env.local` | Supabase Edge Function secret | Edge Function |
| `GOOGLE_TTS_API_KEY` | `.env.local` | Supabase Edge Function secret | Edge Function |
| `SUPABASE_SERVICE_ROLE_KEY` | auto-injected locally | auto-injected by Supabase | Edge Function only |

**Never put `ANTHROPIC_API_KEY`, `GOOGLE_TTS_API_KEY`, or `SUPABASE_SERVICE_ROLE_KEY`
in Flutter client code or commit them to git.**
