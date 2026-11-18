# AI eval set (ADR-019)

Images for checking Create from image without a phone. `cases.json` lists each image with the
mode and size to generate with.

- `draw-*.png`: widgets drawn for this set in the Mono style (Doto for dot numerals): calendar like
  the M5 device test, reminders list, quote, forecast, steps, analog clock, countdown, big date,
  day and zone, a frosted glass card with corner texts and a time pill (ADR-023), and a drawn
  landscape for photo mode. Crops of the third-party reference image
  are never committed (`.gitignore`).

Run it: Actions → **AI eval** → Run workflow (model, review on/off). It needs the repository
secret `GEMINI_API_KEY`. The job generates a spec per image with the app's real prompt, schema,
parser and renderer, and uploads the artifact `ai-eval` with one side-by-side PNG per case
(original left, render right), the specs, and `summary.md`. The key is never printed.

`results/` holds side-by-side images picked from runs, for the record (`m61-*`: the M6.1 provider comparison and local layout fixes, ADR-022). Several models per run: put comma-separated IDs in `model`; raise `pause` for OpenRouter `:free` models. Secrets: `GEMINI_API_KEY`, `NVIDIA_API_KEY`, `OPENROUTER_API_KEY`.

## Interactive cases and the wiring score (ADR-027)

`draw-i-*.png` are drawn with GDI+ for this set: music, streaming card, volume sliders, toggles, control center, timer, calendar agenda, battery of devices, compass, dot clock, smart-home tiles, quick dial, status strip, horizontal sliders. Each case in `cases.json` lists `wiring`: the catalog ids the result must have (`a|b` takes either, `clock` is an analog clock). A case's score is the share of those ids present.

Run them with `cases` = `draw-i-*`. The summary shows the score with the post-pass and from the model alone, and `wiring.json` holds the numbers. With `gate` on, a score under `wiring-best.json` fails the workflow.

`wiring-best.json` and `recorded/` hold the best run. `WiringGateTests.swift` and `CapabilityCatalogTest.kt` replay those replies on every push with no network, so a parser or post-pass change that loses wiring fails CI. After a better run, copy its `<case>.reply.json` files to `recorded/<case>.json` and update `wiring-best.json`.

Before/after for a set of widgets: pass a .zip as base64 in `set_zip` (never committed), and turn on `set_v5` to also rebuild each one with the prompt from a render of the old design. The artifact has `set/set.md` and one image per widget.

## The four rules (ADR-028)

Every interactive case is also scored on live, interactive, alive and correct by `DesignRules`: the share of checked elements that pass. The summary shows them per model, `wiring.json` holds `metrics`, and `wiring-best.json` keeps the best run: `WiringGateTests` and its Kotlin twin replay `recorded/` on every push and fail if any of the four drops. `draw-i-year`, `draw-i-tasks`, `draw-i-mood` and `draw-i-sky` test prompt v6: a year's share is never the battery, a to-do list is `tasks.*`, a face beside a battery is the mood set, a big weather drawing is the weather set.
