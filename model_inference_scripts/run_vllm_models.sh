#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

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

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

DEFAULT_ARGS=()
if is_truthy "${CLINSQL_ENABLE_BATCH_INFERENCE:-}"; then
  DEFAULT_ARGS+=("--enable-batch-inference")
  if [[ -n "${CLINSQL_BATCH_SIZE:-}" ]]; then
    DEFAULT_ARGS+=("--batch-size" "${CLINSQL_BATCH_SIZE}")
  fi
  if [[ -n "${CLINSQL_BATCH_CONCURRENCY:-}" ]]; then
    DEFAULT_ARGS+=("--batch-concurrency" "${CLINSQL_BATCH_CONCURRENCY}")
  fi
  if [[ -n "${CLINSQL_MAX_BATCHED_TOKENS:-}" ]]; then
    DEFAULT_ARGS+=("--max-num-batched-tokens" "${CLINSQL_MAX_BATCHED_TOKENS}")
  fi
  if [[ -n "${CLINSQL_RAY_ADDRESS:-}" ]]; then
    DEFAULT_ARGS+=("--ray-address" "${CLINSQL_RAY_ADDRESS}")
  fi
  if [[ -n "${CLINSQL_RAY_NAMESPACE:-}" ]]; then
    DEFAULT_ARGS+=("--ray-namespace" "${CLINSQL_RAY_NAMESPACE}")
  fi
  if [[ -n "${CLINSQL_RAY_INIT_KWARGS:-}" ]]; then
    DEFAULT_ARGS+=("--ray-init-kwargs" "${CLINSQL_RAY_INIT_KWARGS}")
  fi
fi

if [[ -n "${CLINSQL_VLLM_SERVER_URL:-}" ]]; then
  DEFAULT_ARGS+=("--vllm-server-url" "${CLINSQL_VLLM_SERVER_URL}")
  if [[ -n "${CLINSQL_VLLM_SERVER_API_KEY:-}" ]]; then
    DEFAULT_ARGS+=("--vllm-server-api-key" "${CLINSQL_VLLM_SERVER_API_KEY}")
  fi
  if [[ -n "${CLINSQL_VLLM_SERVER_MODEL:-}" ]]; then
    DEFAULT_ARGS+=("--vllm-server-model" "${CLINSQL_VLLM_SERVER_MODEL}")
  fi
fi

if [[ ${#MODELS[@]} -eq 0 ]]; then
  MODELS=(
    "DeepSeek-R1"
    "DeepSeek-V3.1"
    "Qwen3-Coder-480B-A35B-Instruct"
    "Qwen3-235B-A22B-Instruct"
    "Qwen3-235B-A22B-Thinking-2507-FP8"
    "Qwen3-Next-80B-A3B-Instruct"
    "Qwen3-Next-80B-A3B-Thinking"
    "Llama-4-Maverick-17B-128E-Instruct"
    "Llama-4-Scout-17B-16E-Instruct"
    "SQLCoder-7B-2"
    "MedGemma-27B"
    "Baichuan-M2-32B"
  )
fi

echo "[CLINSQL] Running vLLM inference for ${#MODELS[@]} model(s)."
if [[ ${#DEFAULT_ARGS[@]} -gt 0 ]]; then
  printf '[CLINSQL] Default evaluator args: %s\n' "${DEFAULT_ARGS[*]}"
fi
for model in "${MODELS[@]}"; do
  echo "[CLINSQL] === ${model} ==="
  if is_truthy "${CLINSQL_CLEAN_OUTPUTS:-}"; then
    sanitized_alias="$(
      MODEL_ALIAS="${model}" "${PYTHON_BIN}" - <<'PY'
import os
import re

alias = os.environ["MODEL_ALIAS"]
safe = re.sub(r"[^\w.-]+", "_", alias.strip()).strip("_")
print(safe or "model")
PY
    )"
    output_dir="${REPO_ROOT}/outputs/inference/${sanitized_alias}"
    if [[ -d "${output_dir}" ]]; then
      echo "[CLINSQL] Removing existing outputs at ${output_dir}"
      rm -rf "${output_dir}"
    fi
  fi
  "${PYTHON_BIN}" "${REPO_ROOT}/model_inference/clinical_sql_benchmark_evaluator_vllm.py" \
    --model "${model}" \
    "${DEFAULT_ARGS[@]}" \
    "${EXTRA_ARGS[@]}"
done

echo "[CLINSQL] vLLM inference completed."
