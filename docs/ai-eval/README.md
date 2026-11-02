# AI eval set (ADR-019)

Images for checking Create from image without a phone. `cases.json` lists each image with the
mode and size to generate with.

- `draw-*.png`: widgets drawn for this set in the Mono style (Doto for dot numerals): calendar like
  the M5 device test, reminders list, quote, forecast, steps, analog clock, countdown, big date,
  day and zone, and a drawn landscape for photo mode. Crops of the third-party reference image
  are never committed (`.gitignore`).

Run it: Actions → **AI eval** → Run workflow (model, review on/off). It needs the repository
secret `GEMINI_API_KEY`. The job generates a spec per image with the app's real prompt, schema,
parser and renderer, and uploads the artifact `ai-eval` with one side-by-side PNG per case
(original left, render right), the specs, and `summary.md`. The key is never printed.

`results/` holds side-by-side images picked from runs, for the record (`m61-*`: the M6.1 provider comparison and local layout fixes, ADR-022). Several models per run: put comma-separated IDs in `model`; raise `pause` for OpenRouter `:free` models. Secrets: `GEMINI_API_KEY`, `NVIDIA_API_KEY`, `OPENROUTER_API_KEY`.
