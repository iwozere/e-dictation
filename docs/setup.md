# e-dictation — Setup Guide

Everything you need to do **once** before running the app for the first time.

---

## 1. Prerequisites — install on your machine

| Tool | Min version | Install |
|---|---|---|
| Flutter SDK | 3.44+ | https://docs.flutter.dev/get-started/install |
| Dart | 3.12+ | included with Flutter |
| Node.js | 18+ | https://nodejs.org (needed for Supabase CLI) |
| Supabase CLI | latest | `npm install -g supabase` |
| Docker Desktop | latest | https://www.docker.com/products/docker-desktop (required for `supabase start`) |

Verify Flutter is installed:
```
flutter doctor
```

---

## 2. Supabase — create a cloud project

1. Go to **https://supabase.com** → New project
2. Choose region **eu-central-1** (Frankfurt) for GDPR compliance
3. Save your **project URL** and **anon key** from *Project Settings → API*
4. Save your **service role key** (keep this secret — it bypasses RLS)

---

## 3. Apply the database schema

### Option A — Cloud (recommended for first run)

```bash
# Log in to Supabase CLI
supabase login

# Link your local project to the cloud project
supabase link --project-ref <your-project-ref>

# Push the migration
supabase db push
```

### Option B — Local dev (requires Docker Desktop running)

```bash
supabase start          # starts local Postgres + Auth + Storage
supabase db reset       # applies all migrations from supabase/migrations/
```

Access local Supabase Studio at http://localhost:54323

---

## 4. Enable Anonymous Sign-In

In the Supabase Dashboard:

1. Go to **Authentication → Settings**
2. Enable **Allow anonymous sign-ins**

This is required for students to access dictations without an account.

---

## 5. Google Cloud TTS — get an API key

1. Go to https://console.cloud.google.com
2. Create a project (or use an existing one)
3. Enable the **Cloud Text-to-Speech API**
4. Go to *APIs & Services → Credentials → Create Credentials → API Key*
5. Restrict the key to the Cloud Text-to-Speech API
6. Copy the key — you will add it as an Edge Function secret (step 7)

**Cost:** ~$0.016 per 1,000 characters (Neural2 voices). A typical 200-word dictation
costs about $0.016 total, generated once on save.

---

## 6. Anthropic API key

1. Go to https://console.anthropic.com
2. Create an API key
3. Copy it — you will add it as an Edge Function secret (step 7)

Used only for sentence splitting at dictation save time. A typical dictation
costs fractions of a cent.

---

## 7. Set Edge Function secrets

```bash
supabase secrets set \
  ANTHROPIC_API_KEY=sk-ant-... \
  GOOGLE_TTS_API_KEY=AIza...
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically by
Supabase into every Edge Function — you do not need to set them manually.

---

## 8. Deploy the Edge Function

```bash
supabase functions deploy on_dictation_save
```

To test locally before deploying:
```bash
supabase functions serve on_dictation_save --env-file .env.local
```

Where `.env.local` (never committed) contains:
```
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_TTS_API_KEY=AIza...
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
```

---

## 9. Configure Google OAuth (optional but recommended)

1. In Google Cloud Console, go to *APIs & Services → OAuth consent screen* → configure
2. Go to *Credentials → Create OAuth client ID* → Web application
3. Add authorized redirect URI: `https://<your-project>.supabase.co/auth/v1/callback`
4. In Supabase Dashboard → Authentication → Providers → Google: paste Client ID and Secret
5. Enable Google in `supabase/config.toml` under `[auth.external.google]`

---

## 10. Flutter — install dependencies and run

```bash
# Install packages
flutter pub get

# Run code generation (Riverpod, freezed, json_serializable)
flutter pub run build_runner build --delete-conflicting-outputs

# Run on web (pass your Supabase credentials)
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

For convenience during development, create a `run_web.sh` (gitignored):
```bash
#!/bin/bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

---

## 11. Deploy Flutter Web to Vercel

1. Push this repository to GitHub
2. Import the repo on https://vercel.com
3. Set the **Build Command**:
   ```
   flutter/bin/flutter build web --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
   ```
4. Set the **Output Directory**: `build/web`
5. Add environment variables in Vercel's project settings:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
6. Add this `vercel.json` to the project root for proper SPA routing:
   ```json
   {
     "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }]
   }
   ```

See also: https://docs.flutter.dev/deployment/web

---

## 12. Supabase Storage — CORS (if needed for web)

If browsers block audio requests from the Flutter web app, add a CORS policy in
*Supabase Dashboard → Storage → Policies → CORS*:

```json
[
  {
    "origins": ["*"],
    "methods": ["GET"],
    "headers": ["Range"],
    "exposeHeaders": ["Content-Length", "Content-Range"]
  }
]
```

---

## Summary checklist

- [ ] Flutter SDK + Dart installed
- [ ] Supabase CLI installed + logged in
- [ ] Supabase cloud project created (eu-central-1)
- [ ] Anonymous sign-in enabled in Supabase Dashboard
- [ ] Schema pushed (`supabase db push`)
- [ ] Google Cloud TTS API key obtained
- [ ] Anthropic API key obtained
- [ ] Edge Function secrets set (`supabase secrets set …`)
- [ ] Edge Function deployed (`supabase functions deploy on_dictation_save`)
- [ ] `flutter pub get` + `build_runner build` run
- [ ] App runs locally with `--dart-define` flags
