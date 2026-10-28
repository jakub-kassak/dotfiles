# Writing Assistant

**Cmd+G** copies the selection, waits up to 150 ms, then falls back to the existing
clipboard if nothing was copied. The text is sent to the selected cloud provider.
Do not invoke it on confidential text unless that provider is approved for it.
One to three whitespace-separated words open Lexicon automatically; choose Correct
to check a short sentence instead. Results/history remain in memory (10 entries).

## HUD controls

| Key | Action |
| --- | --- |
| 1 / 2 / 3 / 4 | Correct / Polish / Concise / Formal |
| L | Toggle Lexicon (definition, grammar notes, synonyms, EN/DE/SK translations) |
| Option+E / Option+D / Option+S | Translate to EN / DE / SK |
| D | Diff / Clean |
| C or Cmd+Shift+C | Copy corrected text only |
| Return or Cmd+Return | Replace the original selection, if still valid |
| U | Restore original text to clipboard (not an editor undo) |
| [ / ] or Left / Right | Previous / next history result |
| Escape / outside click | Close and ignore pending responses |

Shortcuts capture those keys while the HUD is visible; close it before typing into
the underlying app. Cmd+C still copies a manually selected portion of the HUD.
Replacement is disabled for clipboard-only checks and historical sessions. It checks
the app, window, and available Accessibility selection information, then checks again
after dismissal. Apps without complete Accessibility support cannot provide perfect
selection identity; use Copy if uncertain. Rich clipboard restoration after replacement
uses a guarded 700 ms delay because macOS has no universal paste-completion signal.

## Credentials and models

Environment variables take precedence over literal assignments in `~/.zsh_secrets`.
The file is parsed, **not executed**; simple quoted/unquoted values and `$NAME` aliases
are supported, not shell commands. No embedded-key or backup-file fallback is used.

```sh
export GOOGLE_API_KEY='your-key'  # GEMINI_API_KEY also supported
export OPENAI_API_KEY='your-key'  # optional
export GEMINI_MODEL='gemini-3.7-flash'
export OPENAI_MODEL='gpt-6.1-sol'
```

The requested model defaults are used verbatim; availability depends on your provider
account/API. An unavailable model produces an error rather than silently selecting
another model/provider. The HUD provider picker remembers your choice. With no saved
choice, OpenAI is preferred when its key exists, otherwise Gemini. Reload after adding
keys if necessary, then press Retry or Cmd+G. OpenAI requests use `store=false`.

Restrict permissions on your secrets file (`chmod 600 ~/.zsh_secrets`). Rotate the
previous hard-coded Google key: it still exists in the explicitly requested backup
`init.lua.before-grammar-upgrade-20261028` (permissions restricted to the owner).

## Preferences (Hammerspoon console)

```lua
hs.settings.set("grammarChecker.englishVariant", "British") -- or American/preserve
hs.settings.set("grammarChecker.preserveTerms", {"AeroSpace", "YourProduct"})
grammarChecker.run({clipboard = true}) -- explicitly skip selection copying
```

The HUD uses a translucent, rounded local HTML card with a native window shadow;
this is not true NSVisualEffectView desktop vibrancy. All model strings are inserted
as text, local code computes the Unicode-aware token diff, navigation/external resources
are blocked, and no credentials are sent to JavaScript. Long inputs are limited to 24 KB;
large diffs use a bounded prefix/suffix fallback to keep the HUD responsive.

## Tests

```sh
hs -c 'dofile(hs.configdir .. "/grammar_checker_test.lua")'
hs -c 'hs.reload()'
```

Tests mock network, clipboard, timers and keystrokes. Real provider availability and
application-specific replacement behavior require a manual check using non-sensitive text.
