---
name: image
description: Use when the user wants to generate or edit a raster image, SVG or animated GIF with the OpenAI Images API (GPT Image, gpt-image-2.6 Sunburst/Flare) — e.g. "draw", "generate an image/picture", "нарисуй", "сгенерируй картинку", photo, illustration, cover, hero image, sprite, texture, mockup, transparent-background cutout, SVG logo or illustration, animated GIF, or editing/varying an existing picture. Not for icons or graphics that must match existing SVGs or a style already in the repo, and not for diagrams that are simpler to build in code.
---

# Image generation with the OpenAI Images API

Images are created and edited by `scripts/image_gen.py` (OpenAI Images API). Claude Code has no built-in image generation tool, so this is the primary path — don't ask the user whether to use the API. OpenAI docs: https://developers.openai.com/api/docs/guides/image-generation (append `.md` for markdown).

Every call goes through the wrapper. It runs the scripts in a uv environment pinned by `scripts/uv.lock` (stored outside the project, so never `pip install` anything) and loads the key:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" --check     # dependencies and whether a key is set
```

Below, `run.sh` means `bash "${CLAUDE_SKILL_DIR}/scripts/run.sh"`. Requires `uv` on PATH (https://docs.astral.sh/uv/); the first run downloads Python packages.

## API key

`OPENAI_API_KEY` from the environment, otherwise the file `~/.config/openai/api_key` (override with `OPENAI_API_KEY_FILE`). If `--check` prints `NOT set`, never ask the user to paste the key into the chat — give these steps:

1. Create a key at https://platform.openai.com/api-keys (the organization may need verification for GPT Image models).
2. Save it: `mkdir -p ~/.config/openai && chmod 700 ~/.config/openai`, put the key into `~/.config/openai/api_key`, then `chmod 600 ~/.config/openai/api_key` — or `export OPENAI_API_KEY=…` in the shell profile.

Never print the key or write it into project files. Without a key, still build the request and run `--dry-run` (no key needed), so a single call remains once the key is set.

## Models

| Model | When |
|---|---|
| `gpt-image-2.6-flare` (**default**) | Fast iterations, drafts, everyday images |
| `gpt-image-2.6-sunburst` | Final assets, precise edits, dense text, complex compositions |
| `gpt-image-2` | Cheapest drafts (`low` 1024×1024 ≈ $0.006); no transparency, `xhigh`/`max`, `complexity`, markup, SVG or GIF |
| `gpt-image-1.5`, `gpt-image-1-mini` | Legacy; sizes 1024×1024, 1536×1024, 1024×1536, `auto` only. `gpt-image-1` was shut down 2026-10-23 |

`gpt-image-2.5-sunburst`/`-flare` have the same features except `complexity`; prefer 2.6. List the models the key can use: `run.sh /dev/stdin <<<'from openai import OpenAI; print(sorted(m.id for m in OpenAI().models.list() if "image" in m.id))'`.

## When not to use

- An icon, logo or graphic that must match an existing SVG or icon set in the repo — edit those as code.
- Simple shapes, diagrams, wireframes — SVG, HTML/CSS, canvas.
- The user explicitly wants a deterministic, code-built result.

## Workflow

1. **Intent:** a new image (`generate`) or a change to an existing one that keeps parts of it (`edit`). Images given "for style" are references for `edit` (the first is the target, the rest are references); no images — `generate`.
2. **Where the result goes.** Previews and drafts — the session scratchpad or a temp directory. A project asset — straight into the right project folder under a descriptive name. Always pass `--out` or `--out-dir`: the script default `output/imagegen/` would litter the repository. Don't overwrite an existing file — use `hero-v2.png` unless the user asked for replacement (`--force`).
3. **Prompt** — use the schema below. Only structure a specific request; add to a generic one only what clearly improves the result (composition, intended use, lighting) — no extra objects, brands or slogans. Models like to add props (plants, vases); if the scene must stay empty, forbid them in `--negative`.
4. **Cheap first:** `--dry-run` when unsure about parameters; drafts at `--quality low`; finals at `medium`/`high` and the needed size. `xhigh`, `max`, 4K and many variants only after the user agrees to the quoted cost.
5. **Run** (from the project root or with absolute paths):

   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" image_gen.py generate \
     --prompt "A minimal hero image of a ceramic coffee mug on a stone surface" \
     --use-case product-mockup \
     --composition "wide shot, mug on the right, empty space on the left for page copy" \
     --constraints "no logos, no text, no watermark" \
     --negative "no plants, no props" \
     --quality low --size 1536x1024 \
     --out "<scratchpad>/mug-hero.png"
   ```

   The only field flags are `--use-case --scene --subject --style --composition --lighting --palette --materials --text --constraints --negative`; the script assembles them into a structured prompt. There are no flags for `Asset type` or `Input images` — put them into `--prompt`, or write the whole prompt yourself and pass `--no-augment` (long prompts via `--prompt-file`). `--scene` is the backdrop in the picture, not transparency (that is `--background`). Many different assets — `generate-batch` with JSONL (model, quality etc. can be overridden per job); `--n` is only for variants of one prompt.
6. **Cost:** after each call the script prints `Usage (...): input_tokens=… output_tokens=…; image output ~$…`. Quote prices from this line, not from memory. Reference point: Flare `low` 1536×1024 ≈ 660 output tokens ≈ $0.02.
7. **Check:** open the result with the `Read` tool (PNG, JPEG, WebP) and compare subject, style, composition, text accuracy and exclusions. SVG — rasterize and `Read` the PNG: on macOS `qlmanage -t -s 1024 -o <dir> logo.svg` → `<dir>/logo.svg.png`; elsewhere `rsvg-convert -w 1024 logo.svg -o logo.png` if available, otherwise read the SVG source. GIF — lay the frames out in a strip and open it (one frame doesn't show whether there is motion, and frames can come out identical):

   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" /dev/stdin anim.gif anim-frames.png <<'EOF'
   import sys; from PIL import Image, ImageSequence
   fr = [f.convert("RGBA") for f in ImageSequence.Iterator(Image.open(sys.argv[1]))]
   print("frames", len(fr), "size", fr[0].size, "ms", [f.info.get("duration") for f in fr])
   s = Image.new("RGBA", (fr[0].width * len(fr), fr[0].height), "white")
   for i, f in enumerate(fr): s.paste(f, (i * fr[0].width, 0))
   s.thumbnail((1600, 800)); s.save(sys.argv[2])
   EOF
   ```

   Iterate with one change at a time, restating the invariants.
8. **Report:** paths to the final files, the final prompt, model, size, quality and the cost from `Usage`.

## Prompt schema

```text
Use case: <slug: photorealistic-natural | product-mockup | ui-mockup | infographic-diagram | ads-marketing | logo-brand | illustration-story | stylized-concept | …>
Asset type: <where it will be used>
Primary request: <the user's main request>
Input images: <Image 1: role; Image 2: role>
Scene/backdrop / Subject / Style/medium / Composition/framing / Lighting/mood / Color palette
Text (verbatim): "<exact text>"
Constraints: <what to keep / what to avoid>
```

For edits always say "change only X, keep Y unchanged". Text in the image goes in quotes with font and placement; spell tricky words letter by letter. Write the description in English (all recipes in the references are English); in-image text goes verbatim in its target language in `Text (verbatim)` — check it especially carefully after generation. Non-ASCII text in `--dry-run` output shows as `\uXXXX`; that is display only.

If important parameters are missing (for a sprite: pixel art or illustration, single frame or sheet, view angle), choose a sensible option yourself for a draft and name it in the report; for a final asset, ask.

## Quality, complexity, sizes

- `--quality`: `low`, `medium` (script default), `high`, `xhigh`, `max`, `auto`; `xhigh`/`max` only on Sunburst/Flare.
- `--complexity` (2.6 only): `low`, `medium`, `high`; the API uses `high` when omitted. It sets how much the model plans before rendering: `high` helps dense text, complex layouts and object relationships but adds latency and unwanted changes. Use `low` for focused edits (background, a sign). No separate fee.
- `--size`: `auto` or `WxH`: both sides multiples of 16, max side 3840, ratio up to 3:1, 655,360–8,294,400 pixels. Common: `1024x1024`, `1536x1024`, `1024x1536`, `2048x2048`, `2048x1152`, `3840x2160`, `2160x3840`. Square is usually fastest.
- `--output-format jpeg` is faster than `png` when latency matters.
- Never pass `--input-fidelity` with `gpt-image-2` (always high).

## Transparent background

Native on Flare/Sunburst: `--background transparent --output-format png` (or `webp`). Verified: the background is fully transparent, but the subject's alpha can be 250–254 instead of 255 (1–2 % see-through). For an asset, raise that alpha to 255:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/run.sh" /dev/stdin in.png out.png <<'EOF'
import sys; from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA"); r, g, b, a = im.split()
Image.merge("RGBA", (r, g, b, a.point(lambda v: 255 if v >= 245 else v))).save(sys.argv[2])
EOF
```

Check the edges with `Read` (composite onto a contrasting color if needed). If the subject is hard (fur, smoke, glass) and the native cutout is poor, fall back to a perfectly flat chroma key (pure `#00ff00`, no shadows or gradients, subject colors far from the key), then `run.sh remove_chroma_key.py --input <name>-key.png --out <name>.png --auto-key border --soft-matte --spill-cleanup`. A key-colored halo — `--edge-contract 1` or a higher `--transparent-threshold`; details eaten — lower `--tolerance`.

## SVG, GIF, markup edits (Sunburst/Flare)

- **SVG:** `generate --output-format svg --n 1 --out logo.svg` — icons and illustrations with editable paths (when matching an existing set isn't required). `generate` only, no `--output-compression`. The image model first draws a raster reference (`--model`, `--quality`, `--complexity`), then a text model writes the SVG. The API requires that model: the script sends `--svg-model gpt-6.2-astra` by default; `--svg-effort none…max` sets its reasoning. The script prints a separate `SVG author usage` line — those tokens are billed at the text model's rates. Verified: a logo with lettering in ~40 s, ~$0.025 for the reference plus ~3,000 author tokens.
- **GIF:** `--output-format gif [--frame-count 2..16 (9)] [--frame-duration-ms 20..2000 (200)]` with `generate` or `edit` (stills as references). Frames are packed into one sheet whose sides are capped at 3840, so large frames don't fit: the API rejects 2 frames of `1024x1024`. Keep `--size auto` (gave 512×512 for 2 frames) or use small frames; on `No supported sheet fits …` reduce the frame size or `--frame-count`. In the prompt describe the subject, the motion per frame and how the loop closes; check with a frame strip that there is motion — if frames are identical, spell out the per-frame motion, add frames or raise quality.
- **Markup:** `edit --image photo.png --markup overlay.png --prompt "Recolor the vase inside the red circle … Keep everything else unchanged. Remove the red circle."` — the overlay is a separate transparent PNG with circles and arrows, the same size as the first image (not flattened onto the photo); not together with `--mask`; at most 16,777,216 pixels. The script checks the overlay's size and transparency.
- **Mask** (`--mask`, any model): a PNG with an alpha channel, same size and format as the first image; the mask is guidance, the model may not follow its exact shape.

## Common mistakes

| Mistake | Do instead |
|---|---|
| Own script or `curl` to the API | Only `image_gen.py` via `run.sh` |
| `pip install openai` / `uv add openai` in the project | The wrapper provides pinned dependencies outside the project |
| No `--out` → files in the repo's `output/imagegen/` | Always pass `--out` / `--out-dir` |
| Starting with `xhigh`/`max`/4K "to try" | Draft at `low`, then the final with consent |
| `--background transparent` with `gpt-image-2` | Flare/Sunburst |
| `unrecognized arguments: --asset-type` | No such flag: put the intended use into `--prompt` |
| `moderation_blocked` (`image_generation_user_error`) | Don't retry as is: change the prompt or input images; `moderation_details.moderation_stage` tells where it was blocked |
| `Connection error` with a key set, or uv failing to download packages on first run | Probably a sandboxed Bash without network — rerun outside the sandbox or ask to allow network |
| Organization verification error / `model not found` | The organization needs access to that model — tell the user; list the available models |

## References

- `references/cli.md` — all flags, edits with masks and markup, `generate-batch`, models and API parameters, prices.
- `references/prompting.md` — prompting principles, text in images, iteration.
- `references/sample-prompts.md` — ready recipes by asset type (website, game, wireframe, logo, infographic, edits).
