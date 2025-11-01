"""Utilities for assembling vLLM inputs for CLINSQL text-to-SQL inference."""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple

from vllm import LLM, SamplingParams

from .model_specs import OpenSourceModelSpec
from .prompt_utils import build_generation_prompt, build_refinement_prompt
from .schema_utils import load_mimic_schema_text


@dataclass(frozen=True)
class VLLMSamplingConfig:
    """Sampling configuration for vLLM text generation."""

    temperature: float = 0.2
    top_p: float = 0.9
    top_k: int = -1
    max_new_tokens: int = 1024
    stop_sequences: Optional[List[str]] = None

    def to_sampling_params(self) -> SamplingParams:
        """Translate this configuration into a vLLM SamplingParams instance."""
        return SamplingParams(
            temperature=self.temperature,
            top_p=self.top_p,
            top_k=self.top_k,
            max_tokens=self.max_new_tokens,
            stop=self.stop_sequences,
        )

    def to_dict(self) -> dict:
        """Return a plain dict representation for REST or Ray integrations."""
        data = {
            "temperature": self.temperature,
            "top_p": self.top_p,
            "max_tokens": self.max_new_tokens,
        }
        if self.top_k >= 0:
            data["top_k"] = self.top_k
        if self.stop_sequences:
            data["stop"] = list(self.stop_sequences)
        return data


@dataclass(frozen=True)
class SQLGenerationRequest:
    """Represents a single prompt for initial SQL generation."""

    question: str


@dataclass(frozen=True)
class SQLRefinementRequest:
    """Represents a prompt that asks the model to refine a failing SQL query."""

    question: str
    previous_sql: str
    error_message: str


def prepare_vllm_engine(
    *,
    spec: OpenSourceModelSpec,
    model_id_override: Optional[str] = None,
    tokenizer_id: Optional[str] = None,
    revision: Optional[str] = None,
    trust_remote_code: Optional[bool] = None,
    tensor_parallel_size: Optional[int] = None,
    dtype: Optional[str] = None,
    gpu_memory_utilization: Optional[float] = None,
    max_model_len: Optional[int] = None,
    download_dir: Optional[str] = None,
    sampling_config: Optional[VLLMSamplingConfig] = None,
    enforce_eager: Optional[bool] = None,
    quantization: Optional[str] = None,
) -> Tuple[LLM, SamplingParams]:
    """Initialise a vLLM engine and paired sampling parameters."""

    model_id = model_id_override or spec.model_id

    llm_kwargs = {
        "model": model_id,
        "tensor_parallel_size": tensor_parallel_size or spec.tensor_parallel_size or 1,
        "dtype": dtype or spec.dtype or "auto",
        "trust_remote_code": spec.trust_remote_code if trust_remote_code is None else trust_remote_code,
        "gpu_memory_utilization": gpu_memory_utilization
        if gpu_memory_utilization is not None
        else spec.gpu_memory_utilization,
    }

    if tokenizer_id or spec.tokenizer_id:
        llm_kwargs["tokenizer"] = tokenizer_id or spec.tokenizer_id
    if revision or spec.revision:
        llm_kwargs["revision"] = revision or spec.revision
    if download_dir:
        llm_kwargs["download_dir"] = download_dir
    if max_model_len or spec.max_model_len:
        llm_kwargs["max_model_len"] = max_model_len or spec.max_model_len
    if enforce_eager is not None or spec.enforce_eager is not None:
        llm_kwargs["enforce_eager"] = enforce_eager if enforce_eager is not None else spec.enforce_eager
    quantization_mode = quantization if quantization is not None else spec.quantization
    if quantization_mode:
        llm_kwargs["quantization"] = quantization_mode

    llm = LLM(**llm_kwargs)
    sampling_params = (sampling_config or VLLMSamplingConfig()).to_sampling_params()
    return llm, sampling_params


def prepare_generation_prompts(
    requests: Sequence[SQLGenerationRequest],
    *,
    schema_text: Optional[str] = None,
) -> List[str]:
    """Render CLINSQL Chain-of-Thought prompts for initial SQL generation."""
    schema = schema_text or load_mimic_schema_text()
    return [build_generation_prompt(req.question, schema) for req in requests]


def prepare_refinement_prompts(
    requests: Sequence[SQLRefinementRequest],
    *,
    schema_text: Optional[str] = None,
) -> List[str]:
    """Render CLINSQL refinement prompts for failed SQL executions."""
    schema = schema_text or load_mimic_schema_text()
    return [
        build_refinement_prompt(
            question=req.question,
            previous_sql=req.previous_sql,
            error_message=req.error_message,
            schema_text=schema,
        )
        for req in requests
    ]


def prepare_generation_batch(
    requests: Sequence[SQLGenerationRequest],
    *,
    spec: OpenSourceModelSpec,
    schema_text: Optional[str] = None,
    sampling_config: Optional[VLLMSamplingConfig] = None,
    **engine_kwargs,
) -> Tuple[List[str], LLM, SamplingParams]:
    """Convenience helper that returns prompts, model handle, and sampling params."""
    prompts = prepare_generation_prompts(requests, schema_text=schema_text)
    llm, sampling_params = prepare_vllm_engine(
        spec=spec,
        sampling_config=sampling_config,
        **engine_kwargs,
    )
    return prompts, llm, sampling_params


def prepare_refinement_batch(
    requests: Sequence[SQLRefinementRequest],
    *,
    spec: OpenSourceModelSpec,
    schema_text: Optional[str] = None,
    sampling_config: Optional[VLLMSamplingConfig] = None,
    **engine_kwargs,
) -> Tuple[List[str], LLM, SamplingParams]:
    """Convenience helper for refinement prompts plus the vLLM runtime."""
    prompts = prepare_refinement_prompts(requests, schema_text=schema_text)
    llm, sampling_params = prepare_vllm_engine(
        spec=spec,
        sampling_config=sampling_config,
        **engine_kwargs,
    )
    return prompts, llm, sampling_params
