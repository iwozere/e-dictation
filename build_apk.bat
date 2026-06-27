@echo off
REM Build a release APK for a physical device against the HOSTED Supabase project.
REM The phone cannot reach localhost:54321 — it must use the cloud URL.
REM Output: build\app\outputs\flutter-apk\app-release.apk
flutter build apk --release --dart-define-from-file=dart_defines.hosted.json
