# CLI reference (`scripts/image_gen.py`)

Source of truth: https://developers.openai.com/api/docs/guides/image-generation (append `.md` for markdown). Facts below checked against it on 2026-11-20.

All commands go through the wrapper, which runs the scripts in a uv environment pinned by `scripts/uv.lock` (kept outside the project) and loads the key:

```bash
IMAGEGEN="${CLAUDE_SKILL_DIR}/scripts/run.sh"   # set by Claude Code for this skill
bash "$IMAGEGEN" --check                      # deps + whether OPENAI_API_KEY is set
bash "$IMAGEGEN" image_gen.py generate --prompt "Test" --out "$OUT/test.png" --dry-run
```

Subcommands: `generate` (new image), `edit` (change existing images; first `--image` is the edit target, the rest are references), `generate-batch` (many prompts from JSONL). `--dry-run` prints the payload and output paths without a network call or key; it also runs all client-side validation.

## Guardrails
- Do **not** create one-off runners (for example `gen_images.py`) unless the user explicitly asks for a custom wrapper. If the API gained a feature the script lacks, extend `image_gen.py` (and note the change in the repository's `NOTICE`).
- Ask before `xhigh`/`max` quality, 4K sizes, or many variants; quote the cost from the `Usage` line of a draft.

## Defaults
- Model: `gpt-image-2.6-flare`
- Size: `auto`
- Quality: `medium` (script default; the API default is `auto`)
- Output format: `png`
- Default output path (`output/imagegen/output.png`) — never rely on it; pass `--out`
- Background, complexity: unset unless passed (API complexity default is `high`)

## Models

| Model | Quality | Sizes | Transparent | Complexity / markup / SVG / GIF | Use |
| --- | --- | --- | --- | --- | --- |
| `gpt-image-2.6-flare` | low…max, auto | flexible | yes | yes | Default: fast iteration, everyday images |
| `gpt-image-2.6-sunburst` | low…max, auto | flexible | yes | yes | Detailed work, precise edits, dense text |
| `gpt-image-2.5-flare` / `-sunburst` | low…max, auto | flexible (above 2560x1440 experimental) | yes | markup, SVG, GIF; complexity is documented for 2.6 | Previous generation |
| `gpt-image-2` | low, medium, high, auto | flexible | no | no | Cheapest drafts |
| `gpt-image-1.5`, `gpt-image-1-mini`, `chatgpt-image-latest` | low, medium, high, auto | 1024x1024, 1536x1024, 1024x1536, auto | 1.5: yes | no | Legacy; `input_fidelity` low/high |
| `gpt-image-1` | — | — | — | — | Shut down 2026-10-23 |

"low…max" = `low`, `medium`, `high`, `xhigh`, `max`. The script groups models by prefix: `gpt-image-2.5-*`/`2.6-*` (next), legacy names above (fixed sizes), anything else `gpt-image-*` (flexible sizes, quality up to `high`). Dated snapshots (`gpt-image-2-2026-04-21`, `gpt-image-2.5-flare-2026-09-08`) follow their base model. Options the docs do not pin to a model (`input_fidelity` on 2.5/2.6, `complexity` on 2.5) are passed through; the API rejects them if unsupported.

Flexible size: `auto` or `WIDTHxHEIGHT`, both multiples of 16, max edge 3840, long:short ≤ 3:1, total 655,360–8,294,400 pixels. Popular: `1024x1024` (fastest), `1536x1024`, `1024x1536`, `2048x2048`, `2048x1152`, `3840x2160`, `2160x3840`.

## Quality and complexity
- `--quality low` for drafts; compare higher settings for finals. `xhigh`/`max` only on Sunburst/Flare.
- `--complexity low|medium|high` (2.6): how much the model plans before rendering. Lower suits focused edits (background, a sign); higher helps dense text, complex layouts, object relationships, but adds latency and can introduce unwanted changes. No separate fee.
- `--input-fidelity` (edit-only) — never with `gpt-image-2` (always high fidelity, which also raises input tokens for edits with references).

```bash
bash "$IMAGEGEN" image_gen.py generate \
  --model gpt-image-2.6-sunburst \
  --prompt "A polished landing-page hero image of a matte ceramic mug on a stone surface" \
  --quality high --size 2048x1152 \
  --out "$OUT/mug-hero.png"
```

## Transparent background

Flare/Sunburst: `--background transparent --output-format png|webp`. Verified 2026-11-20 on `gpt-image-2.6-flare`: background alpha 0, subject alpha 250–254 (clamp to 255 for assets — snippet in SKILL.md).

```bash
bash "$IMAGEGEN" image_gen.py generate \
  --prompt "A cute orange cat game sprite, full body, side view, isolated on a transparent background, no shadow" \
  --background transparent --output-format png --quality low --size 1024x1024 \
  --out "$OUT/cat.png"
```

Fallback for hard edges (fur, smoke, glass): flat chroma key + local removal:

```bash
bash "$IMAGEGEN" remove_chroma_key.py --input "$OUT/sprite-key.png" --out "$OUT/sprite.png" --auto-key border --soft-matte --spill-cleanup
```

Then `Read` the result to check edges (composite on a contrasting color if needed). Options: `--key-color`, `--tolerance`, `--transparent-threshold`, `--opaque-threshold`, `--edge-contract`, `--edge-feather`, `--force`. No `--dry-run`.

## SVG output
`generate --output-format svg --n 1` only. No `edit`, no streaming, no `--output-compression`; SVG is not a valid edit input. The image model (`--model`, `--quality`, `--complexity`) makes a raster reference; an authoring text model writes static SVG (no scripts, external resources or embedded rasters). The API requires `svg.model` (error `SVG generation requires 'svg.model'` otherwise — the guide does not mention it, the API reference does): the script sends `--svg-model` (default `gpt-6.2-astra`) and optional `--svg-effort none|minimal|low|medium|high|xhigh|max`; batch jobs get the default or a per-job `"svg": {"model": …}`. Cost = reference image tokens + author tokens (`svg_usage`, printed as `SVG author usage`, billed at the author's text rates). Verified 2026-11-20: Flare `low` reference 824 output tokens + astra 1,615 in / 1,512 out, ~39 s. View: `qlmanage -t -s 1024 -o <dir> logo.svg` → `<dir>/logo.svg.png`.

```bash
bash "$IMAGEGEN" image_gen.py generate --output-format svg \
  --prompt "Flat vector logo for a bakery called Field & Flour: golden loaf above a two-line wordmark" \
  --text "Field & Flour" --out "$OUT/logo.svg"
```

## Animated GIF output
`--output-format gif` on `generate` or `edit` (still images as references). `--frame-count` 2–16 (default 9), `--frame-duration-ms` 20–2000, rounded to 10 (default 200); these flags require gif. `--size` is per frame (`auto` or multiples of 16). Frames are packed into a sheet whose longest edge must stay ≤ 3840, so large frames fail: 2 × `1024x1024` → `No supported sheet fits 2 GIF frames at size '1024x1024'`. Prefer `auto` (gave 512×512 for 2 frames) or small frames; on that error reduce frame size, `--frame-count` or `--n`. No streaming, no masks, no `--output-compression`; downscale is skipped. Describe subject, per-frame motion and how the loop closes. Verified 2026-11-20: valid 2-frame looping GIF, but both frames came out identical with a vague prompt and `low` — always inspect a frame strip (snippet in SKILL.md).

```bash
bash "$IMAGEGEN" image_gen.py generate --model gpt-image-2.6-sunburst --output-format gif \
  --frame-count 9 --frame-duration-ms 200 \
  --prompt "A monkey in a green coat lifts a glowing lantern, blinks, lowers it; seamless loop back to the start pose" \
  --out "$OUT/lantern.gif"
```

## Edits: references, masks, markup

```bash
bash "$IMAGEGEN" image_gen.py edit \
  --image room.png --image sofa-reference.png \
  --prompt "Image 1: edit target. Image 2: reference. Replace only the sofa in Image 1 with the sofa from Image 2; keep everything else unchanged" \
  --complexity low \
  --out "$OUT/room-v2.png"
```

- Repeated `--image`: order matters; describe each by index and role. The guide's example uses 4 inputs; it states no maximum (older docs said 16).
- `--mask`: single PNG with alpha, same size and format as the first image, under 50 MB; applies to the first image; prompt-guided, shape not exact.
- `--markup` (Sunburst/Flare): separate transparent PNG overlay with circles/sketches for the first image — same size after orientation, must contain transparent pixels (not flattened), ≤ 16,777,216 pixels, ≤ 50 MB; not with `--mask`; no extra fee. The script checks all of this. Ask the model to remove the annotation:

```bash
bash "$IMAGEGEN" image_gen.py edit --image kitchen.png --markup overlay.png --quality medium \
  --prompt "Recolor the striped vase inside the red circle to solid cobalt blue ceramic. Keep its shape, the dried stems, and the rest of the kitchen unchanged. Remove the red circle from the finished photo." \
  --no-augment --out "$OUT/kitchen-vase.png"
```

- Repeat invariants in every iteration (`change only X; keep Y unchanged`).

## Output handling
- Always pass `--out` / `--out-dir`; the script default `output/imagegen/` would litter the current repo.
- Put scratch JSONL files in the session scratchpad, not the repo.
- Reruns fail if a target exists unless `--force`.
- `--out-dir` names one-off outputs `image_1.<ext>`, `image_2.<ext>`, …
- `--downscale-max-dim N` writes an extra `-web` copy (raster formats only).
- `--output-format jpeg` is faster than png; `--output-compression 0-100` for jpeg/webp.
- After each call the script prints `Usage (<model>): input_tokens=… output_tokens=…; image output ~$…` (output tokens × $30/M for gpt-image-2+; input tokens extra).

## Batch

```bash
mkdir -p "$OUT/batch"
cat > "$OUT/prompts.jsonl" << 'EOF'
{"prompt":"Cavernous hangar interior with a compact shuttle parked near the center","use_case":"stylized-concept","composition":"wide-angle, low-angle","constraints":"no logos or trademarks; no watermark","size":"1536x1024","out":"hangar.png"}
{"prompt":"Gray wolf in profile in a snowy forest","use_case":"photorealistic-natural","model":"gpt-image-2.6-sunburst","quality":"high","out":"wolf.png"}
EOF
bash "$IMAGEGEN" image_gen.py generate-batch --input "$OUT/prompts.jsonl" --out-dir "$OUT/batch" --concurrency 5
rm -f "$OUT/prompts.jsonl"
```

- `--out-dir` required; per-job `out` is a filename under it.
- Per-job overrides: `model`, `size`, `quality`, `complexity`, `background`, `output_format`, `output_compression`, `frame_count`, `frame_duration_ms`, `moderation`, `n`, `out`, prompt fields. Each job is validated separately.
- `--concurrency` (default 5), `--max-attempts` (default 3, retries rate limits and server errors), `--fail-fast`.
- One job per distinct asset; `--n` is only for variants of one prompt.

## API facts

- Endpoints: `POST /v1/images/generations`, `POST /v1/images/edits`; result `data[].b64_json` (the script decodes it).
- Parameters: `prompt`, `model`, `n` (1–10), `size`, `quality`, `complexity`, `background` (`transparent|opaque|auto` — output transparency, not the scene), `output_format` (`png|jpeg|webp|svg|gif`), `output_compression`, `moderation` (`auto` default, `low` less restrictive), `frame_count`, `frame_duration_ms`; edit adds `image`, `mask`, `markup`, `input_fidelity`. Also exist, not exposed by the script: `stream` + `partial_images` (0–3, +100 output tokens each), `safety_identifier` (hashed end-user id ≤ 128 chars; replaces deprecated `user`).
- Responses API (`tools: [{"type": "image_generation", "model": "gpt-image-2.6-flare"}]`, mainline `gpt-5`+) adds multi-turn edits via `previous_response_id`, file-ID inputs, and `revised_prompt`; this CLI uses the Images API only.
- Pricing (per 1M tokens, 2026-11): gpt-image-2 / 2.5 / 2.6 — image in $8, image out $30, text in $5 (batch API half). gpt-image-1.5 — image out $32; gpt-image-1-mini — image out $8. Token counts differ by model and quality, so equal rates ≠ equal cost per image; measure with `usage`. Historical per-image (1024x1024): gpt-image-2 low $0.006 / medium $0.053 / high $0.211; gpt-image-1-mini low $0.005 / medium $0.011 / high $0.036. Measured: Flare 2.6 low 1536x1024 = 664 output tokens ≈ $0.02.
- Errors: `error.type = image_generation_user_error` (e.g. `code = moderation_blocked`, optional `moderation_details.moderation_stage` `input|output`) — change the prompt or inputs, don't retry as is. Retry rate-limit and server errors with backoff; never auto-retry quota errors.
- Limitations: complex prompts up to ~2 min; precise text placement, recurring-character consistency and exact layout can still fail.
- Organization verification may be required before using GPT Image models.
