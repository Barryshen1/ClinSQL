"""Shared utilities for CLINSQL inference and evaluation."""

from .constant import (
    REPO_ROOT,
    BENCHMARK_DOMAINS,
    BENCHMARK_DIFFICULTIES,
    BENCHMARK_SPLITS,
)
from .schema_utils import load_mimic_schema_text
from .sql_utils import clean_sql_response
from .prompt_utils import build_generation_prompt, build_refinement_prompt
from .model_specs import (
    ProprietaryModelSpec,
    PROPRIETARY_MODEL_SPECS,
    SUPPORTED_PROPRIETARY_MODELS,
    OpenSourceModelSpec,
    OPEN_SOURCE_MODEL_SPECS,
    OPEN_SOURCE_MODEL_ALIASES,
    SUPPORTED_OPEN_SOURCE_MODELS,
    resolve_open_source_model_alias,
)
from .api_utils import create_proprietary_client
try:  # Optional dependency for vLLM workflows
    from .vllm_prepare_input import (
        VLLMSamplingConfig,
        SQLGenerationRequest,
        SQLRefinementRequest,
        prepare_vllm_engine,
        prepare_generation_prompts,
        prepare_refinement_prompts,
        prepare_generation_batch,
        prepare_refinement_batch,
    )
except ModuleNotFoundError:  # pragma: no cover - vLLM not installed
    VLLMSamplingConfig = None  # type: ignore
    SQLGenerationRequest = None  # type: ignore
    SQLRefinementRequest = None  # type: ignore
    prepare_vllm_engine = None  # type: ignore
    prepare_generation_prompts = None  # type: ignore
    prepare_refinement_prompts = None  # type: ignore
    prepare_generation_batch = None  # type: ignore
    prepare_refinement_batch = None  # type: ignore

__all__ = [
    "REPO_ROOT",
    "BENCHMARK_DOMAINS",
    "BENCHMARK_DIFFICULTIES",
    "BENCHMARK_SPLITS",
    "build_generation_prompt",
    "build_refinement_prompt",
    "clean_sql_response",
    "load_mimic_schema_text",
    "ProprietaryModelSpec",
    "PROPRIETARY_MODEL_SPECS",
    "SUPPORTED_PROPRIETARY_MODELS",
    "OpenSourceModelSpec",
    "OPEN_SOURCE_MODEL_SPECS",
    "OPEN_SOURCE_MODEL_ALIASES",
    "SUPPORTED_OPEN_SOURCE_MODELS",
    "resolve_open_source_model_alias",
    "create_proprietary_client",
    "VLLMSamplingConfig",
    "SQLGenerationRequest",
    "SQLRefinementRequest",
    "prepare_vllm_engine",
    "prepare_generation_prompts",
    "prepare_refinement_prompts",
    "prepare_generation_batch",
    "prepare_refinement_batch",
]
