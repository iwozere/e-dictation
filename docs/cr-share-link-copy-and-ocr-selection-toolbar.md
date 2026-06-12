# CR: Share Link Copy & OCR Text Selection Toolbar

## Summary

Two small UX fixes on the teacher side:
1. The dictation detail page now copies a fully-qualified share URL (suitable for pasting into an email) instead of a bare share code or a protocol-less hostname.
2. The dictation text field receives keyboard focus immediately after OCR populates it, so the native Cut / Copy / Select All toolbar appears correctly on mobile.

---

## Fix 1 — Copy full share link

### Problem

The "Copy share link" button in the AppBar was writing `e-dictation.app/d/XXXXXX` to the clipboard (wrong domain, no protocol). The clipboard icon inside the share-code banner was copying only the bare 6-character code. Neither was directly pasteable as a working hyperlink.

### Changes

| File | Change |
|---|---|
| `lib/core/config/app_config.dart` | Added `appBaseUrl` compile-time constant (defaults to `https://e-dictation.vercel.app`; overridable via `--dart-define=APP_BASE_URL=...`) |
| `lib/features/dictations/presentation/screens/dictation_detail_screen.dart` | Both copy actions now write `${AppConfig.appBaseUrl}/d/${shareCode}`. Snackbar message changed from generic "Copied!" to "Link copied!" |

### Behaviour after fix

- The share-code banner still displays the short 6-char code for verbal sharing.
- Tapping the clipboard icon (banner) or the share icon (AppBar) copies `https://e-dictation.vercel.app/d/F8A46B` — ready to paste into an email or message.
- The base URL is a build-time constant so a future custom domain (`https://e-dictation.app`) only requires one `--dart-define` change.

---

## Fix 2 — OCR text selection toolbar on mobile

### Problem

After "Scan from image" extracts text and sets it via `_textCtrl.text = text`, the text field had no keyboard focus. On Android and iOS, the editing toolbar (Cut / Copy / Select All) only appears when the field is the active text input. Without calling `requestFocus()`, the toolbar was suppressed even though text selection handles were visible.

A secondary issue: the word-count indicator was rendered inside a `Stack` on top of the `TextFormField`. This created a widget layered over the field that could interfere with Flutter's selection-toolbar overlay positioning.

### Root cause

`TextEditingController.text = value` is a programmatic assignment; it does not request focus or notify the platform's input connection. Mobile IME and selection-toolbar logic is gated on the field holding input focus.

### Changes

| File | Change |
|---|---|
| `lib/features/dictations/presentation/screens/create_dictation_screen.dart` | Added `_textFocusNode` (`FocusNode`); wired to `TextFormField.focusNode`; `requestFocus()` called after OCR callback. Replaced `Stack` word-count overlay with a plain `TextFormField` + `Align` below it. |
| `lib/features/dictations/presentation/screens/edit_dictation_screen.dart` | Same changes as create screen. |

### Behaviour after fix

- Immediately after OCR populates the field, the keyboard opens and the field is in edit mode.
- Long-pressing any word shows the native selection handles **and** the Cut / Copy / Select All toolbar.
- The word count (`N / 500`) is displayed below the field (right-aligned) instead of overlaid inside a `Stack`.
