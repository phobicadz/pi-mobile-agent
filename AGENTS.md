# AGENTS.md — Pi Mobile Agent

A Flutter web app + Node backend that drives a `pi --mode rpc` child process over
WebSocket. The backend serves the built web bundle and the WebSocket from the **same
port (3000)**, so a phone or laptop on the LAN just opens `http://<host>:3000`.

## This machine is the deployment target

`ubuntu-mancave` (this box, `192.168.2.1` / `desktop.mancave`) **is** where the app
runs. Do not SSH to deploy — build and restart here.

```bash
./deploy/install-service.sh            # build backend + web bundle, install unit, restart
./deploy/install-service.sh --no-web   # backend only, skip the Flutter build
```

The script is idempotent and safe to re-run after every change. It needs no sudo
(systemd **user** unit + `loginctl enable-linger`).

## Commands

| Task | Command |
| --- | --- |
| Build + deploy everything | `./deploy/install-service.sh` |
| Backend only | `cd backend && npm install --include=dev && npm run build` |
| Backend dev server (watch) | `cd backend && npm run dev` (tsx, port 3000) |
| Frontend only | `cd frontend && ~/flutter/bin/flutter pub get && ~/flutter/bin/flutter build web` |
| Frontend analyze / test | `cd frontend && ~/flutter/bin/flutter analyze` · `flutter test` |
| Backend tests | no test script — `backend/package.json` has only `dev`, `build`, `start`. Check a backend change against a throwaway instance (`PORT=3999 node dist/index.js`) over a WebSocket, so the live service is not touched |
| Service status / logs | `systemctl --user status pi-mobile-agent` · `journalctl --user -u pi-mobile-agent -n 100 --no-pager` |
| Restart / stop | `systemctl --user restart\|stop pi-mobile-agent` |
| Health check | `curl http://localhost:3000/health` → `{"status":"ok","pi_connected":true,...}` |
| App | `http://192.168.2.1:3000` |

**Flutter is not on PATH in non-interactive shells.** It lives at `~/flutter/bin/flutter`;
the deploy script finds it itself, but a hand-run `flutter` command needs the full path.
`npm run build` must be run with devDependencies present (`tsc` is one).

## Architecture

```
backend/src/index.ts        Express + WebSocket server; owns currentCwd, spawns `pi --mode rpc`,
                            relays every Pi event to all connected clients
backend/src/pi-rpc-client.ts  RPC protocol wrapper over the pi child's stdio
backend/src/session-store.ts  Reads Pi's on-disk session history (list_sessions, sessionCwdOf)
backend/src/fs-browser.ts     Directory/file browsing for the app's folder picker
frontend/lib/main.dart        Entry; resolves the WebSocket URL (web: same host that served the page)
frontend/lib/services/pi_service.dart   WebSocket client, command send + event/state streams
frontend/lib/providers/pi_view_model.dart  All app state (ChangeNotifier)
frontend/lib/models/pi_models.dart      Wire types (PiState, PiMessage, PiModel, PiUsage, …)
frontend/lib/screens/home_screen.dart   Chat screen + AppBar + drawer menu
frontend/lib/widgets/                 chat_list, chat_bubble, file_browser, model_selector, context_meter
frontend/lib/utils/chat_palette.dart    The chat's colours, read off the active theme + colour scheme
frontend/lib/utils/code_theme.dart      Which syntax palette the code is coloured with, on the ThemeData
frontend/lib/utils/editor_palettes.dart The editor themes' surfaces *and* their syntax palettes
frontend/lib/utils/dracula_scheme.dart  Dracula's palette, authored rather than seeded
frontend/lib/providers/appearance_controller.dart  Theme mode, colour scheme, text sizes (ChangeNotifier)
```

Adding a command end-to-end: `pi-rpc-client.ts` method → `case` in `index.ts` →
method in `pi_service.dart` → `PiViewModel` → widget. See `DEVELOPMENT.md`. A command
Pi does not carry (`set_notifications`) starts at the `case` in `index.ts` instead.

## Non-obvious constraints (read before editing)

- **Pi's cwd is fixed at spawn time.** There is no RPC `set_cwd`. Changing the working
  directory means **respawning the Pi child process** in the new directory. `currentCwd`
  is mutable; `piProcessCwd` is where the running child was actually spawned — keep them
  distinct so a resume follows Pi instead of guessing.
- **Pi's RPC `get_state` has no cwd.** The backend injects `cwd`, `cwdDisplay` (shrinkHome)
  and `gitBranch` into every state response. Anything the app bar shows about the
  directory has to come from those injected fields. `sessionName` is the other way round:
  Pi reports it and the backend passes it through untouched — it is absent when the session
  has no name, which is the app's signal to show nothing.
- **Sessions are persisted** (no `--no-session`) so `/resume` can reload them. Resuming
  re-enters the directory recorded in the session file.
- **`PI_PROVIDER` / `PI_MODEL` are unset in the unit on purpose** — Pi uses its own
  configured provider/model. Set them only to override.
- **The web build needs no `--dart-define`**: it connects to the host that served the
  page. Native builds do need `SERVER_URL`.
- **A session name is an appended entry, never an edited header.** Pi's format is a
  `session_info` record hanging off the last entry, so renaming appends one and the
  *last* one in the file wins — including a nameless one, which is how Pi clears a
  name. Editing the header instead would leave the old name winning, and appending to
  the file the live Pi is itself appending to is how a half-written line gets into a
  session: rename the live one through RPC `set_session_name`, and only touch files
  nobody has open directly.
- **`pi --print` reads the prompt from stdin**, which is how a title request gets its
  conversation without putting it in an argument. Wrap what you pipe in delimiters (the
  backend uses `<conversation>…</conversation>`): a bare block of text on stdin reads to
  a model as something to answer rather than something to name.
- **The "agent finished" notification is not the app's.** It is sent by the
  `notify-completion` extension in the `pi-setup` Pi package
  (`~/.pi/agent/git/github.com/phobicadz/pi-setup/extensions/`), on `agent_settled`,
  from inside the Pi child process. The app's switch reaches it through a file both
  sides can read: `~/.pi/agent/pi-mobile-notifications.json` (`PI_NOTIFY_PREFS` to move
  it), written by `backend/src/notification-prefs.ts` and read by the extension at notify
  time — so it is **one setting for every device and every Pi session on this box**, not a
  per-browser preference. Missing or unreadable means on. Editing that extension only
  takes effect after a service restart: Pi loads extensions when it starts.
- **Port 3000 is unauthenticated LAN HTTP.** Don't expose it beyond the LAN without a
  reverse proxy with auth/WSS.

## Gotchas hit before

- **`Icons.git_commit` and `Icons.source_branch` do not exist** in the Flutter version
  pinned here (3.47.7 stable). `Icons.merge_type` and `Icons.folder_open` do. A bad
  `Icons.*` name only fails at the web compile step, with `Error: Member not found:`.
- **Do not use `Theme.of(context).colorScheme.onAppBar`** — it isn't a ColorScheme member.
  AppBar children inherit the right foreground colour; leave icon colours unset.
- **The AppBar's title box is width-limited by the AppBar itself**, so a flex in the
  `title` can only fill that box — never reach the right edge of the bar. Anything that
  belongs at the right end (the git chip) goes in `actions`, which is what the bar actually
  right-aligns. Measured positions are the way to check this: `tester.getRect(...)` at both a
  phone width and a desktop width, because centring only shows up when the window is wide.
- **The session name is anchored to the right end of the title area, not centred.**
  `Expanded(flex: 1, folder)` then `Flexible(flex: 1, fit: loose, Align(centerRight, name))`: the
  directory holds the left half, the name the right, flush with the edge the bar already right-aligns
  its own controls to. Two reasons, both measured at a phone and a desktop width in
  `test/appbar_session_name_test.dart`.
  - Centring needed a counterweight: an identical empty box on the name's right, a third of the title
    area doing nothing, which at 390px was the difference between a readable directory name and an
    icon with one character after it (14px of text). Anchoring spends nothing on balance.
  - Centring also made the name's position a function of its own length — a bar whose centre shifts
    as you work. Anchored, a short name and a long one end in the same place, and the directory keeps
    the room it was given either way; the two tests are comparisons of a short name against a long one
    because that is what the design promises.
  - And **centring a box is not centring the words in it**, which is what the old failure looked
    like: the middle box *was* exactly centred (`Expanded(a)`, name, `Expanded(a)`), and the name
    control filled it, so the words started where the control's own Row put them — half an icon
    (18 + 6 = 24, so 12px) right of the middle, at every width. If anything here is ever centred
    again, the icon in front of the name has to be paid for by the same width of nothing on its other
    side.
- **Don't put `Expanded`/`Flexible` inside a `Tooltip`'s child.** The widget a
  `Tooltip` keeps in place is laid out with no width constraint of its own, so a
  flex child inside that Row throws `RenderFlex children have non-zero flex but
  incoming width constraints are unbounded`. Put the flex in the outer Row and the
  `Tooltip` inside it, wrapping the `Text` directly. Only visible when the branch
  data is actually present, so a test that supplies a `gitBranch` is what catches it.
- `flutter build web` prints a harmless `Expected to find fonts for ... cupertino_icons`
  warning and a wasm dry-run notice. Success is the final `✓ Built build/web`.
- `systemctl --user …` from a non-login shell may need `XDG_RUNTIME_DIR`; the service
  itself is fine — verify with `systemctl --user is-active pi-mobile-agent`.
- A `PiViewModel` field that the AppBar reads must be exposed through the ViewModel and
  fed from `piService.stateUpdates`, not read from a widget-local state.
- **When you are driving this repo *from* the app, you are the service's child process.**
  The tree is `systemd → node dist/index.js → pi → your tool calls`, so
  `systemctl --user restart pi-mobile-agent` stops the node process, which stops the Pi
  running you, which ends the tool call with `SIGTERM` (exit 143). The restart still
  succeeds — it just outlives the command that asked for it.
- **App chrome reads its colours from `ColorScheme` tokens; a hardcoded `Colors.*` in a widget is a bug the moment another scheme is chosen.** It looked like the theme was half-applied twice now: first in the chat bubbles, then in the model picker (a `grey.shade300` box, `redAccent`, `grey.shade600`) and the composer's hairline. The exceptions are deliberate and few: tool-output green, the connection dot's green/red, the context meter's amber, and the code-highlight theme in the file viewer — those are signals or a code theme, not styling. A dropdown *menu* already follows the theme (`Theme.canvasColor` is `colorScheme.surface` under Material 3); it is the control around it that needs the tokens.
- **In `utils/code_highlight.dart`, `shell` is registered as the `bash` grammar.** The shipped `shell` grammar is a *session* grammar: it colours what follows a `$ ` prompt and treats the rest as output, so a script on disk, a ```bash fence, or the command in a tool call comes out with no colour at all. Same class of fix as the corrected `xml` grammar already in that file.
- **A tool call's arguments are rendered as arguments** (`ChatBubble._buildToolArgs`): one per line, monospace, parameter name as a label, and a shell command — recognised by `ChatBubble.isShellTool` — gets the syntax colouring. They used to be one `key: value, key: value` line in the reply's proportional text, which is why a command read as prose. The result gets the same label treatment (`_toolLabel`, “output”): an unlabelled block under a command is just more text in the card.
- **An `edit` is rendered as a diff, in the language of the file it edits.** The `edits` list is unpacked into one block per half (`_diffBlocks`), removed before added, because `[{oldText: <4 lines>, newText: <5 lines>}]` is the shape of an edit rather than the edit. The language comes from the *path* argument (`languageForPath`, `isProsePath` → `plaintext` for a document) — never from the text, which is how a shell command gets coloured by a Dart grammar. The two halves are told apart by more than their labels: `ChatPalette.diffAdded` / `diffRemoved` on the label and as a 3px bar that *is* the block's left edge (`_diffRadius`: square against the bar, rounded away from it), and `addedBlock` / `removedBlock` — the code surface with the signal blended into it at 14% / 8%, faintly because a tint strong enough to be a swatch is a tint the code theme's token colours stop working on. Those two colours are fixed like the tool-output green: a `+`/`-` that changes with the user's colour preference stops meaning anything. A `Row` with `CrossAxisAlignment.stretch` inside a `Column` is asked for a height it is never given, which is why the bar is a border on a wrapper.
- **Every block of code *in a reply* takes the theme's surfaces (`ChatPalette.codeBackground` / `codeForeground`)** — a fenced block, a tool call's command, a tool's output. They used to take the code theme's fixed grey, which is the same colour in every scheme, so a reply ended up in two palettes: a Dracula bubble holding an atom-one-dark block. Recess the block *toward the page* at either brightness, which is a different token per theme (`surfaceContainer` in dark, `surfaceContainerLowest` in light) — the same direction in both sits proud of its card at one brightness and sunk into it at the other. `CodeTheme.codeSurface` is the one place that direction is written down; ask it rather than picking the token again.
- **Whichever surface the code is on owns the colour of the text between the tokens.** On the app's surface that is the app's text (`colorScheme.onSurface`), so a path or a subcommand a grammar leaves alone reads as text. On a code theme's *own* background — which is what the file viewer paints — it is that theme's own foreground, because a code theme is a set of colours for one surface and not for any surface. `CodeTheme.foregroundFor(codeBackground, appText:)` decides which, and it is the answer to a question every caller used to answer differently.
- **The file viewer keeps the code theme's own surface, on purpose.** Its token colours were chosen against that background, and painting them on the app's background is what once made the colouring look wrong — differently in light and in dark. That reasoning is recorded in `file_viewer.dart`; don't "unify" it with the chat without re-checking it. It costs nothing when the code theme *is* the app's palette: the theme's surface and the app's are then the same colour.
- **`CodeTheme` (`utils/code_theme.dart`) is a `ThemeExtension`, and it is how picking Solarized colours strings in Solarized green.** It rides on the `ThemeData` `main.dart` builds, because every widget that draws code already has a theme and none of them has the colour scheme — a code theme threaded through eight constructors is one that gets forgotten in the ninth. `CodeTheme.following(scheme, brightness)` derives the syntax palette from `EditorPalette.syntax` (an `EditorSyntax`: comment / keyword / string / number / title / variable / type / tag hues, which is what a theme publishes); `CodeTheme.of(theme)` is what every renderer asks, and a theme without the extension gets the app default rather than nothing. Two rules a new theme has to keep:
  - **A token colour is only legible relative to the block it is drawn on.** `mapFor(codeBackground)` re-derives the map per surface and raises each token to ≥4.0:1 *in lightness only* (hue preserved, asserted in `test/code_theme_test.dart`) — which is why Atom One Light's green, 3.2:1 on a Material light surface, stops being an invisible grey. The one exception is the default theme on its own background: `fixedMap` is the stock `flutter_highlight` map, unchanged, which is what "the app default is the app default" has to mean before anything else.
  - **A seeded scheme, and a dark-only theme in light mode, has no syntax palette to follow** and gets the default. Deriving one from a Material seed hue would be the app inventing a theme and naming it after a scheme that only ever asked for a hue. `AppColorScheme.authoredAt(brightness)` is the question both `schemeFor` and `CodeTheme.following` ask.
- **Theme ids belong in every cache key that holds rendered code.** A span tree has its token colours baked into it as literally as a rendered bubble does, so `highlightedSpans` takes a `themeId` and `ChatPalette` carries `codeThemeId` into `cacheKey`. A cache keyed on source, language and brightness will happily hand back another theme's colours after the scheme changes, which is the bug the bubble cache already had.
- **A tool call's long text is folded at 12 lines behind a count** (`_FoldedText` in `chat_bubble.dart`, `_previewLines`). A `write` of a 400-line file made a card taller than the phone, and the question a card answers is *what changed, roughly* — which is in the first few lines. The number is in the control before the tap (`show all 20 lines` → `show the first 12 lines`), because how much you are about to open is what you want to know before you agree to opening it. Folding keeps the bar, the tint and the language: a preview is not a reason to stop colouring a diff half as the file it is.
- **An editing tool's result is plain text, not a code block** (`_buildToolResult`, `ChatBubble.isEditTool` — by name *and* by shape: any call carrying an edit pair). “Successfully replaced 2 block(s).” used to be drawn as highlighted code because `_looksLikeCode` matched the `k(` in `block(s)`. A command's output keeps the code block, the syntax colours and the output green — it *is* content. A failed edit (`^Error` / `^Failed`) is the one status line that is not quiet.
- **Text in a tool card that is not the card's content** — a path, an offset, a status line — uses `ChatPalette.toolText`, which is `legibleOn(onSurfaceVariant, toolCard)`: the quiet token nudged toward the far end of the card until it clears 4.5:1, and no further. `onSurfaceVariant` is *quiet*, not *legible* — under Dracula it is 3.07:1 on the tool card, which is why the path looked washed out. Where the token already clears 4.5 (every light scheme, most dark ones) `toolText` *is* the token, unchanged. `contrastOn` / `legibleOn` are public in `chat_palette.dart`; use them instead of trusting that a Material token is readable on a surface you picked yourself.
- **A new colour scheme is a case in `AppColorScheme`, not a `ThemeData` edit.** The seeded ones (`blue`…`red`) are just a case. An editor theme is a case *plus* an `EditorPalette` in `utils/editor_palettes.dart` — the theme's own background, text, comment grey, primary/tertiary/error accents, and its `raised` step where the theme publishes one. The **surface scale is derived, never invented**: a step from the background toward the page, and one step toward the text. Themes publish a background and a current-line colour, not a five-step Material scale, and a hex invented to fill that gap and then called “the theme's colour” is a claim the file cannot keep. The tonal *spacing* (containers, `on*` pairs) still comes from `ColorScheme.fromSeed` seeded on the palette's own accent. `utils/dracula_scheme.dart` stays hand-authored — it predates this, its tests name its constants, and its surface steps are Dracula's own published ones.
- **`legibleOn` / `contrastOn` (in `utils/chat_palette.dart`) are how a palette is checked, not guessed.** An accent too dim for the surface it is drawn on is raised in *lightness* only — a lerp toward black or white scales a colour's channels without changing which dominates, so the hue is untouched, and a test asserts that (a raised accent is the same theme; a *replaced* accent is a different theme with the old name). `EditorPalette` applies it to primary/tertiary/error/muted; `Dracula` applies it to its red (`#FF5555` on its own bubble is 3.75:1). `test/editor_palettes_test.dart` runs the whole chat palette — reply text, your text, the Pi accent, the quiet text in a card, code on its block, both halves of a diff — at ≥4.5:1 for **every** scheme at **both** brightnesses, plus the two roles ≥45° of hue apart and a card a visible step off its bubble. Adding a theme without earning those is how a palette gets shipped that is unreadable on a phone.
- **A dark-only theme in light mode is generated from its own hue, and says so.** `AppColorScheme.isDarkOnly` drives the picker's note; `schemeFor` authors a palette only where one exists at that brightness. Solarized, Atom One and GitHub ship light halves; Dracula, Nord, Catppuccin, Tokyo Night and Monokai do not, and pretending otherwise means painting a light mode with dark surfaces. `main.dart` asks the choice how it is built at each brightness (`schemeFor`), so a seed-based scheme is one enum case plus a colour, and an authored palette like Dracula is one enum case plus a file like `utils/dracula_scheme.dart`. A scheme that only exists at one brightness has to say so in the picker (`note`) — a swatch cannot admit that a palette is dark-only.
- **The chat's colours come from `utils/chat_palette.dart`, not from literals in `chat_bubble.dart`.** They were hardcoded hex before, which meant a chosen colour scheme changed the bar and left the chat blue. Keep new chat colours as `ColorScheme` token *pairs* (`primaryContainer`/`onPrimaryContainer`, `onSurface` on a `surfaceContainer*`) — those are the combinations Material 3 generates to be legible on each other at either brightness for any seed, which is what the literals were imitating. Tool *results* stay green on purpose: that one is a signal, not a style.
- **`_BubbleBodyCache` keys on the whole palette** (`ChatPalette.cacheKey`), not just brightness. A cached bubble body is a finished subtree with literal colours in it, so a key that misses the colour scheme hands every message in the chat back in the colours it was drawn with before the change — the same trap the text size already had to avoid.
- **The compact view drops the *result* half of a tool card and nothing else.** The name, the arguments, a shell command in shell colours, an edit's diff and everything Pi wrote stay exactly as they are: the mode is a shorter view of the same turn, not a shorter turn. A tool call with no arguments still renders as its name — with nothing run and nothing printed, the card is the fact that something happened.
- **A view mode is a constructor argument and a cache-key component, never a `context.watch` inside a bubble.** `AppearanceController.compactChat` → `HomeScreen` → `ChatList.compact` → `ChatBubble.compact`, exactly the path `fontScale` takes, for the same reason: a bubble that read the setting for itself would not be part of the signature its cached body is stored under, and toggling the setting would leave every message in the shape it had before. Adding a mode to `ChatBubble` means adding it to `_signatureOf` in the same change.
- **A viewing choice lives in `AppearanceController` and the browser store; an agent-wide setting does not.** Theme mode, colour scheme, both text sizes and the compact view are per device (`pi-mobile-agent.compactChat` in localStorage, `loadCompactChat`/`saveCompactChat`). The notifications switch is the opposite case — it silences an extension running inside the Pi child process — so the backend owns it and every device shares it. Put a new setting on the right side of that line.
- **The menu has more than one `Switch` now**, so `find.byType(Switch)` is not a control — it is whichever row the menu built first, and a tap on it moves the wrong setting. Use `menuSwitch(title)` from `test/support/app_menu.dart`, which scopes to the row by its title. The titles are state-dependent wording, so a caller names the state it expects and a row that failed to change when pressed is simply not found.
- **A frontend-only change needs no restart.** The backend serves `frontend/build/web`
  from disk with `no-store` on `index.html`, so `flutter build web` is live on the next
  page load. Restart only for a backend change. When in doubt, compare
  `curl -s localhost:3000/main.dart.js | grep -c <a-string-only-the-new-code-has>`
  against the same count in `frontend/build/web/main.dart.js` — they must match.

## Style

- TypeScript ESM (`"type": "module"`), Node 18+ (22 on this box). `tsc` → `backend/dist`.
- Dart: follow the existing file-comment style — this codebase explains *why* in comments,
  not just *what*. Match that when touching `home_screen.dart`, `pi_view_model.dart`, etc.
- Keep tool/UI behaviour independent where a non-interactive mode could hit it.
- Don't add a dependency without a real need; the frontend deliberately keeps the tree small.

## Repo docs

`README.md` (overview) · `DEPLOYMENT.md` (service install, unit config, current host) ·
`DEVELOPMENT.md` (dev workflow, adding a command) · `API_REFERENCE.md` (WebSocket protocol) ·
`PROJECT_STRUCTURE.md` · `QUICKSTART.md` · `CHECKLIST.md`. Several `*_SUMMARY.md` files are
dated change notes, not current docs — don't treat them as authoritative.

## Definition of done

For any change: build it (`./deploy/install-service.sh`), confirm
`curl localhost:3000/health` is ok, and push to `main` (`https://github.com/phobicadz/pi-mobile-agent`).
Restart the service only when a **backend** file changed — and see the child-process note
above before doing that from inside the app.
