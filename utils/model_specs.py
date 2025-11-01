"""Model metadata shared across inference scripts."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Literal, Optional, Tuple


@dataclass(frozen=True)
class ProprietaryModelSpec:
    provider: Literal["azure_openai", "google_gemini", "xai_grok", "mistral"]
    api_model: str
    azure_deployment: Optional[str] = None
    azure_api_version: str = "2024-12-01-preview"
    use_responses_api: bool = False
    api_key_env: Optional[str] = None
    base_url: Optional[str] = None
    default_temperature: float = 0.1  # Optional hint for chat sampling


PROPRIETARY_MODEL_SPECS: Dict[str, ProprietaryModelSpec] = {
    "GPT-5": ProprietaryModelSpec(
        provider="azure_openai",
        api_model="gpt-5-chat",
        azure_deployment="gpt-5-chat",
        default_temperature=1.0,
    ),
    "GPT-5-chat": ProprietaryModelSpec(
        provider="azure_openai",
        api_model="gpt-5-chat",
        azure_deployment="gpt-5-chat",
        default_temperature=1.0,
    ),
    "GPT-5-mini": ProprietaryModelSpec(
        provider="azure_openai",
        api_model="GPT-5-mini",
        azure_deployment="GPT-5-mini",
        default_temperature=1.0,
    ),
    "GPT-5-nano": ProprietaryModelSpec(
        provider="azure_openai",
        api_model="GPT-5-nano",
        azure_deployment="GPT-5-nano",
        default_temperature=1.0,
    ),
    "GPT-4.1": ProprietaryModelSpec(
        provider="azure_openai",
        api_model="GPT-4.1",
        azure_deployment="GPT-4.1",
        use_responses_api=True,
        azure_api_version="2025-03-01-preview",
    ),
    "o4-mini": ProprietaryModelSpec(
        provider="azure_openai",
        api_model="o4-mini",
        azure_deployment="o4-mini",
        use_responses_api=True,
        azure_api_version="2025-03-01-preview",
    ),
    "Gemini-2.5-Pro": ProprietaryModelSpec(
        provider="google_gemini",
        api_model="gemini-2.5-pro",
    ),
    "Gemini-2.5-Flash": ProprietaryModelSpec(
        provider="google_gemini",
        api_model="gemini-2.5-flash",
    ),
    "Grok-4-Fast-Reasoning": ProprietaryModelSpec(
        provider="xai_grok",
        api_model="grok-4-fast-reasoning",
        api_key_env="XAI_API_KEY",
        base_url="https://api.x.ai/v1",
    ),
    "Grok-4-Fast-Non-Reasoning": ProprietaryModelSpec(
        provider="xai_grok",
        api_model="grok-4-fast-non-reasoning",
        api_key_env="XAI_API_KEY",
        base_url="https://api.x.ai/v1",
    ),
    "Mistral-Medium": ProprietaryModelSpec(
        provider="mistral",
        api_model="mistral-medium",
        api_key_env="MISTRAL_API_KEY",
    ),
}

SUPPORTED_PROPRIETARY_MODELS = list(PROPRIETARY_MODEL_SPECS.keys())


@dataclass(frozen=True)
class OpenSourceModelSpec:
    model_id: str
    tokenizer_id: Optional[str] = None
    revision: Optional[str] = None
    trust_remote_code: bool = True
    dtype: Optional[str] = "auto"
    tensor_parallel_size: Optional[int] = 1
    gpu_memory_utilization: Optional[float] = 0.9
    max_model_len: Optional[int] = None
    enforce_eager: Optional[bool] = None
    quantization: Optional[str] = None


OPEN_SOURCE_MODEL_SPECS: Dict[str, OpenSourceModelSpec] = {
    "DeepSeek-R1": OpenSourceModelSpec(
        model_id="deepseek-ai/DeepSeek-R1",
        trust_remote_code=True,
        dtype="bfloat16",
    ),
    "DeepSeek-V3.1": OpenSourceModelSpec(
        model_id="deepseek-ai/DeepSeek-V3.1",
        trust_remote_code=True,
        dtype="bfloat16",
    ),
    "Qwen3-Coder-480B-A35B-Instruct": OpenSourceModelSpec(
        model_id="Qwen/Qwen3-Coder-480B-A35B-Instruct",
        trust_remote_code=True,
        dtype="bfloat16",
    ),
    "Qwen3-235B-A22B-Instruct": OpenSourceModelSpec(
        model_id="Qwen/Qwen3-235B-A22B-Instruct-2507",
        trust_remote_code=True,
        dtype="bfloat16",
    ),
    "Qwen3-235B-A22B-Thinking-2507-FP8": OpenSourceModelSpec(
        model_id="Qwen/Qwen3-235B-A22B-Thinking-2507-FP8",
        trust_remote_code=True,
        dtype="bfloat16",
    ),
    "Qwen3-Next-80B-A3B-Instruct": OpenSourceModelSpec(
        model_id="Qwen/Qwen3-Next-80B-A3B-Instruct",
        trust_remote_code=True,
        dtype="bfloat16",
    ),
    "Qwen3-Next-80B-A3B-Thinking": OpenSourceModelSpec(
        model_id="Qwen/Qwen3-Next-80B-A3B-Thinking",
        trust_remote_code=True,
        dtype="bfloat16",
    ),
    "Llama-4-Maverick-17B-128E-Instruct": OpenSourceModelSpec(
        model_id="meta-llama/Llama-4-Maverick-17B-128E-Instruct",
        trust_remote_code=True,
    ),
    "Llama-4-Scout-17B-16E-Instruct": OpenSourceModelSpec(
        model_id="meta-llama/Llama-4-Scout-17B-16E-Instruct",
        trust_remote_code=True,
    ),
    "SQLCoder-7B-2": OpenSourceModelSpec(
        model_id="defog/sqlcoder-7b-2",
        trust_remote_code=True,
        enforce_eager=True,
        max_model_len=49152,
    ),
    "MedGemma-27B": OpenSourceModelSpec(
        model_id="google/medgemma-27b-text-it",
        trust_remote_code=True,
        dtype="bfloat16",
        tensor_parallel_size=2,
        enforce_eager=True,
        max_model_len=49152,
    ),
    "Baichuan-M2-32B": OpenSourceModelSpec(
        model_id="baichuan-inc/Baichuan-M2-32B",
        trust_remote_code=True,
        dtype="bfloat16",
        tensor_parallel_size=2,
        gpu_memory_utilization=0.85,
        enforce_eager=True,
    ),
}

OPEN_SOURCE_MODEL_ALIASES: Dict[str, str] = {
    "deepseek-ai/DeepSeek-R1": "DeepSeek-R1",
    "deepseek-ai/DeepSeek-V3.1": "DeepSeek-V3.1",
    "Qwen/Qwen3-Coder-480B-A35B-Instruct": "Qwen3-Coder-480B-A35B-Instruct",
    "Qwen/Qwen3-235B-A22B-Instruct-2507": "Qwen3-235B-A22B-Instruct",
    "Qwen/Qwen3-235B-A22B-Thinking-2507-FP8": "Qwen3-235B-A22B-Thinking-2507-FP8",
    "Qwen/Qwen3-Next-80B-A3B-Instruct": "Qwen3-Next-80B-A3B-Instruct",
    "Qwen/Qwen3-Next-80B-A3B-Thinking": "Qwen3-Next-80B-A3B-Thinking",
    "meta-llama/Llama-4-Maverick-17B-128E-Instruct": "Llama-4-Maverick-17B-128E-Instruct",
    "meta-llama/Llama-4-Scout-17B-16E-Instruct": "Llama-4-Scout-17B-16E-Instruct",
    "defog/sqlcoder-7b-2": "SQLCoder-7B-2",
    "google/medgemma-27b-text-it": "MedGemma-27B",
    "baichuan-inc/Baichuan-M2-32B": "Baichuan-M2-32B",
}


def resolve_open_source_model_alias(name: str) -> Tuple[str, OpenSourceModelSpec]:
    """Return the canonical alias and spec for an open-source model."""
    canonical = OPEN_SOURCE_MODEL_ALIASES.get(name, name)
    if canonical not in OPEN_SOURCE_MODEL_SPECS:
        raise KeyError(f"Unknown open-source model: {name}")
    return canonical, OPEN_SOURCE_MODEL_SPECS[canonical]


def list_all_open_source_model_names() -> List[str]:
    """Return canonical names plus known aliases without duplicates."""
    names: List[str] = list(OPEN_SOURCE_MODEL_SPECS.keys())
    for alias in OPEN_SOURCE_MODEL_ALIASES:
        if alias not in names:
            names.append(alias)
    return names


SUPPORTED_OPEN_SOURCE_MODELS = list_all_open_source_model_names()
