@echo off
REM Run the app in DEBUG on a connected Android device/emulator.
REM A phone/emulator cannot reach the host's localhost:54321, so we use the
REM HOSTED Supabase project (dart_defines.hosted.json).
flutter run --dart-define-from-file=dart_defines.hosted.json
