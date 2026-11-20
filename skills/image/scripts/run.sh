#!/usr/bin/env bash
# Run pixmint's bundled scripts in a uv-managed environment pinned by uv.lock
# (never touches the current project's virtualenv).
#
# API key: OPENAI_API_KEY from the environment, otherwise read from the file
# ${OPENAI_API_KEY_FILE:-~/.config/openai/api_key}. The key is never printed.
#
# Usage: bash run.sh <image_gen.py|remove_chroma_key.py|/dev/stdin> [args...]
#        bash run.sh --check
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key_file="${OPENAI_API_KEY_FILE:-$HOME/.config/openai/api_key}"
if [[ -z "${OPENAI_API_KEY:-}" && -r "$key_file" ]]; then
  OPENAI_API_KEY="$(tr -d '[:space:]' < "$key_file")"
  export OPENAI_API_KEY
fi

# Keep the environment outside the plugin folder, which is replaced on update.
export UV_PROJECT_ENVIRONMENT="${PIXMINT_VENV:-${XDG_CACHE_HOME:-$HOME/.cache}/pixmint/venv}"
uvrun=(uv run --locked --quiet --project "$here" python -I)

if [[ "${1:-}" == "--check" ]]; then
  "${uvrun[@]}" -c 'import openai, PIL; print("openai", openai.__version__, "| pillow", PIL.__version__)'
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then echo "OPENAI_API_KEY: set"; else echo "OPENAI_API_KEY: NOT set"; fi
  exit 0
fi

script="${1:?pass image_gen.py, remove_chroma_key.py or /dev/stdin}"
shift
[[ "$script" == */* ]] || script="$here/$script"
exec "${uvrun[@]}" "$script" "$@"
