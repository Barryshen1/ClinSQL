#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

# Parse arguments: models before '--', additional evaluator args after.
MODELS=()
EXTRA_ARGS=()
after_double_dash=false
for arg in "$@"; do
  if [[ "${arg}" == "--" ]]; then
    after_double_dash=true
    continue
  fi
  if [[ "${after_double_dash}" == true ]]; then
    EXTRA_ARGS+=("${arg}")
  else
    MODELS+=("${arg}")
  fi
done

if [[ ${#MODELS[@]} -eq 0 ]]; then
  MODELS=(
    "GPT-5"
    "GPT-5-mini"
    "GPT-5-nano"
    "GPT-4.1"
    "o4-mini"
    "Gemini-2.5-Pro"
    "Gemini-2.5-Flash"
    "Grok-4-Fast-Reasoning"
    "Grok-4-Fast-Non-Reasoning"
    "Mistral-Medium"
  )
fi

echo "[CLINSQL] Running proprietary inference for ${#MODELS[@]} model(s)."
for model in "${MODELS[@]}"; do
  echo "[CLINSQL] === ${model} ==="
  case "${model}" in
    GPT-5|GPT-5-mini|GPT-5-nano|GPT-4.1|o4-mini)
      : "${AZURE_OPENAI_ENDPOINT:?Set AZURE_OPENAI_ENDPOINT before running Azure models.}"
      : "${AZURE_OPENAI_API_KEY:?Set AZURE_OPENAI_API_KEY before running Azure models.}"
      ;;
    Gemini-2.5-Pro|Gemini-2.5-Flash)
      : "${GOOGLE_CLOUD_API_KEY:?Set GOOGLE_CLOUD_API_KEY before running Gemini models.}"
      ;;
    Grok-4-Fast-Reasoning|Grok-4-Fast-Non-Reasoning)
      : "${XAI_API_KEY:?Set XAI_API_KEY before running Grok models.}"
      ;;
    Mistral-Medium)
      : "${MISTRAL_API_KEY:?Set MISTRAL_API_KEY before running Mistral models.}"
      ;;
  esac
  "${PYTHON_BIN}" "${REPO_ROOT}/model_inference/clinical_sql_benchmark_evaluator_CoT.py" \
    --model "${model}" \
    "${EXTRA_ARGS[@]}"
done

echo "[CLINSQL] Proprietary inference completed."
