"""
Clinical SQL Benchmark Evaluator (vLLM CoT)

 Evaluate open-source LLM text-to-SQL capabilities on clinical data (MIMIC-IV)
 using chain-of-thought prompting with optional self-refinement. Loads models
 through the vLLM runtime and saves artifacts under outputs/inference/.

 Supported open-source models (Section 5.1, ClinSQL paper):
 DeepSeek-R1, DeepSeek-V3.1, Qwen3-Coder-480B-A35B-Instruct,
 Qwen3-235B-A22B-Instruct, Qwen3-235B-A22B-Thinking-2507-FP8,
 Qwen3-Next-80B-A3B-Instruct, Qwen3-Next-80B-A3B-Thinking,
 Llama-4-Maverick-17B-128E-Instruct, Llama-4-Scout-17B-16E-Instruct,
 SQLCoder-7B-2, MedGemma-27B, Baichuan-M2-32B.

 Each alias resolves to a HuggingFace checkpoint via utils.model_specs.
 Use --model-id-override when you need to point to a different local or hosted
 checkpoint while keeping the paper-aligned alias for reporting.
"""

import os
import json
import time
import re
import pandas as pd
import logging
import shutil
import argparse
from typing import Dict, List, Tuple, Optional, Any
from pathlib import Path
from google.cloud import bigquery
import torch

from utils import (
    BENCHMARK_DIFFICULTIES,
    BENCHMARK_DOMAINS,
    BENCHMARK_SPLITS,
    SUPPORTED_OPEN_SOURCE_MODELS,
    OpenSourceModelSpec,
    resolve_open_source_model_alias,
    clean_sql_response,
    load_mimic_schema_text,
    prepare_vllm_engine,
    VLLMSamplingConfig,
    SQLGenerationRequest,
    SQLRefinementRequest,
    prepare_generation_prompts,
    prepare_refinement_prompts,
)

def _sanitize_model_alias(model_id: str) -> str:
    """Create a filesystem-friendly alias for a model identifier."""
    safe = re.sub(r"[^\w.-]+", "_", model_id.strip())
    safe = safe.strip("_")
    return safe or "model"


def _is_truthy(value: Optional[str]) -> bool:
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "on"}


class VLLMSQLGenerator:
    """Generate and refine SQL using a vLLM-hosted open-source model."""

    def __init__(
        self,
        *,
        model_alias: str,
        spec: OpenSourceModelSpec,
        model_id_override: Optional[str] = None,
        tokenizer_id: Optional[str] = None,
        revision: Optional[str] = None,
        dtype: Optional[str] = None,
        tensor_parallel_size: Optional[int] = None,
        trust_remote_code: Optional[bool] = None,
        download_dir: Optional[str] = None,
        gpu_memory_utilization: Optional[float] = None,
        max_model_len: Optional[int] = None,
        temperature: float = 0.2,
        top_p: float = 0.9,
        top_k: int = -1,
        max_new_tokens: int = 1024,
        stop_sequences: Optional[List[str]] = None,
        enforce_eager: Optional[bool] = None,
        server_url: Optional[str] = None,
        server_api_key: Optional[str] = None,
        server_model: Optional[str] = None,
        enable_batch_inference: bool = False,
        batch_size: Optional[int] = None,
        batch_concurrency: Optional[int] = None,
        max_num_batched_tokens: Optional[int] = None,
        ray_address: Optional[str] = None,
        ray_namespace: Optional[str] = None,
        ray_init_kwargs: Optional[Dict[str, Any]] = None,
    ):
        if prepare_vllm_engine is None:  # pragma: no cover - safety guard
            raise RuntimeError("vLLM is not available; install the vllm package to continue.")

        self.schema_text = load_mimic_schema_text()
        self.model_alias = model_alias
        self.spec = spec
        self.quantization_mode = spec.quantization if spec.quantization else None

        if self.model_alias == "SQLCoder-7B-2" and not os.environ.get("VLLM_ALLOW_LONG_MAX_MODEL_LEN"):
            # SQLCoder prompts include rich schema context; allow longer inputs safely.
            os.environ["VLLM_ALLOW_LONG_MAX_MODEL_LEN"] = "1"

        sampling_kwargs = dict(
            temperature=temperature,
            top_p=top_p,
            top_k=top_k,
            max_new_tokens=max_new_tokens,
            stop_sequences=stop_sequences,
        )
        if model_alias == "SQLCoder-7B-2":
            sampling_kwargs.update(
                {
                    "temperature": 0.0,
                    "top_p": 1.0,
                }
            )
        self.sampling_config = VLLMSamplingConfig(**sampling_kwargs)

        self.server_client = None
        self.use_server_backend = server_url is not None
        self.batch_enabled = bool(enable_batch_inference) and not self.use_server_backend
        self.attempt_ray_batch = self.batch_enabled and (
            _is_truthy(os.environ.get("CLINSQL_USE_RAY"))
            or bool(ray_address)
            or bool(ray_init_kwargs)
        )
        self._ray = None
        self._ray_initialized = False
        self.batch_size = batch_size or 32
        self.batch_concurrency = batch_concurrency or 1
        self.max_num_batched_tokens = max_num_batched_tokens or 16384
        self.ray_address = ray_address
        self.ray_namespace = ray_namespace
        self.ray_init_kwargs = dict(ray_init_kwargs or {})

        self.model_id = model_id_override or spec.model_id
        self.llm = None
        self.sampling_params = None
        self.ray_enabled = False
        self.batch_engine_kwargs: Dict[str, Any] = {}
        self._engine_kwargs: Dict[str, Any] = {}

        if self.use_server_backend:
            try:
                from openai import OpenAI  # type: ignore
            except ImportError as exc:  # pragma: no cover - optional dependency
                raise RuntimeError("The `openai` package is required for server-backed inference.") from exc

            base_url = server_url.rstrip("/") if server_url else ""
            if base_url and not base_url.endswith("/v1"):
                base_url = f"{base_url}/v1"
            api_key = server_api_key or os.environ.get("VLLM_SERVER_API_KEY", "EMPTY")
            self.server_client = OpenAI(base_url=base_url or None, api_key=api_key)
            self.model_id = server_model or self.model_id
            logging.info("Using OpenAI-compatible vLLM server at %s", base_url or "http://localhost:8000/v1")
        else:
            self._engine_kwargs = {
                "spec": spec,
                "model_id_override": model_id_override,
                "tokenizer_id": tokenizer_id,
                "revision": revision,
                "trust_remote_code": trust_remote_code,
                "tensor_parallel_size": tensor_parallel_size,
                "dtype": dtype,
                "gpu_memory_utilization": gpu_memory_utilization,
                "max_model_len": max_model_len,
                "download_dir": download_dir,
                "sampling_config": self.sampling_config,
                "enforce_eager": enforce_eager,
            }
            if self.quantization_mode:
                self._engine_kwargs["quantization"] = self.quantization_mode

            if self.attempt_ray_batch:
                try:
                    os.environ.setdefault("RAY_USE_DEFAULT_LOOP", "1")
                    import ray  # type: ignore
                    from packaging.version import Version
                    from ray.data.llm import build_llm_processor, vLLMEngineProcessorConfig
                except ImportError as exc:  # pragma: no cover - optional dependency
                    raise RuntimeError(
                        "Ray Data >= 2.44.1 is required for batch inference. Install with `pip install \"ray[data]>=2.44.1\"`."
                    ) from exc

                if Version(ray.__version__) < Version("2.44.1"):
                    raise RuntimeError("Ray version must be at least 2.44.1 to enable batch inference.")

                self._ray = ray
                self._build_llm_processor = build_llm_processor
                self._vllm_processor_config_cls = vLLMEngineProcessorConfig
                self.ray_enabled = True
                self.batch_engine_kwargs = {
                    "model": self.model_id,
                    "tensor_parallel_size": tensor_parallel_size or spec.tensor_parallel_size or 1,
                    "dtype": dtype or spec.dtype or "auto",
                    "trust_remote_code": spec.trust_remote_code if trust_remote_code is None else trust_remote_code,
                }
                if self.quantization_mode:
                    self.batch_engine_kwargs["quantization"] = self.quantization_mode
                if gpu_memory_utilization is not None or spec.gpu_memory_utilization is not None:
                    self.batch_engine_kwargs["gpu_memory_utilization"] = (
                        gpu_memory_utilization if gpu_memory_utilization is not None else spec.gpu_memory_utilization
                    )
                if max_model_len or spec.max_model_len:
                    self.batch_engine_kwargs["max_model_len"] = max_model_len or spec.max_model_len
                if download_dir:
                    self.batch_engine_kwargs["download_dir"] = download_dir
                if enforce_eager is not None or spec.enforce_eager is not None:
                    self.batch_engine_kwargs["enforce_eager"] = (
                        enforce_eager if enforce_eager is not None else spec.enforce_eager
                    )
            else:
                if self.batch_enabled:
                    logging.info(
                        "Using local vLLM batch mode (chunk_size=%s)",
                        self.batch_size,
                    )
                self._ensure_local_engine()

    def _build_generation_prompt(self, question: str) -> str:
        if self.model_alias == "SQLCoder-7B-2":
            return self._build_sqlcoder_generation_prompt(question)

        prompts = prepare_generation_prompts(
            [SQLGenerationRequest(question=question)],
            schema_text=self.schema_text,
        )
        return prompts[0]

    def _ensure_local_engine(self) -> bool:
        if self.use_server_backend:
            return False
        if self.llm is not None and self.sampling_params is not None:
            return True
        if not self._engine_kwargs:
            logging.error("Local vLLM engine configuration is missing.")
            return False
        try:
            logging.info("Loading vLLM model: %s", self.model_id)
            self.llm, self.sampling_params = prepare_vllm_engine(**self._engine_kwargs)
            return True
        except Exception as exc:
            logging.error("Failed to initialise vLLM engine: %s", exc)
            self.llm = None
            self.sampling_params = None
            return False

    def _build_refine_prompt(self, question: str, previous_sql: str, error_message: str) -> str:
        if self.model_alias == "SQLCoder-7B-2":
            return self._build_sqlcoder_refine_prompt(question, previous_sql, error_message)

        prompts = prepare_refinement_prompts(
            [
                SQLRefinementRequest(
                    question=question,
                    previous_sql=previous_sql,
                    error_message=error_message,
                )
            ],
            schema_text=self.schema_text,
        )
        return prompts[0]

    def _run_llm(self, prompt: str) -> str:
        if self.use_server_backend and self.server_client is not None:
            try:
                request_kwargs: Dict[str, Any] = {
                    "model": self.model_id,
                    "input": prompt,
                    "temperature": self.sampling_config.temperature,
                    "top_p": self.sampling_config.top_p,
                    "max_output_tokens": self.sampling_config.max_new_tokens,
                }
                if self.sampling_config.stop_sequences:
                    request_kwargs["stop"] = self.sampling_config.stop_sequences
                response = self.server_client.responses.create(**request_kwargs)
            except Exception as exc:  # pragma: no cover - network or server failure
                logging.error("Server-backed vLLM generation failed: %s", exc)
                return ""

            text = getattr(response, "output_text", None)
            if not text:
                parts: List[str] = []
                for item in getattr(response, "output", []) or []:
                    if isinstance(item, dict) and item.get("type") == "output_text":
                        parts.append(item.get("text", ""))
                    elif hasattr(item, "text"):
                        parts.append(getattr(item, "text", ""))
                text = "".join(parts)
            return clean_sql_response((text or "").strip())

        if not self._ensure_local_engine():
            logging.error("vLLM local engine is not initialised.")
            return ""

        try:
            outputs = self.llm.generate([prompt], self.sampling_params)
        except Exception as exc:
            logging.error("vLLM generation failed: %s", exc)
            return ""

        if not outputs:
            logging.error("vLLM returned no generations.")
            return ""

        first = outputs[0]
        if not getattr(first, "outputs", None):
            logging.error("vLLM produced empty output list.")
            return ""

        text = first.outputs[0].text
        return clean_sql_response(text.strip())

    def _build_sqlcoder_generation_prompt(self, question: str) -> str:
        schema_section = ""
        if self.schema_text:
            schema_section = (
                "### Database Schema\n"
                "The query will run on a database with the following schema:\n"
                f"{self.schema_text.strip()}\n\n"
            )

        return (
            "### Task\n"
            f"Generate a SQL query to answer [QUESTION]{question}[/QUESTION]\n\n"
            f"{schema_section}"
            "### Constraints\n"
            "- Target platform: Google BigQuery.\n"
            "- Use only `physionet-data.mimiciv_3_1_hosp` and `physionet-data.mimiciv_3_1_icu` datasets.\n"
            "- Return a single valid BigQuery statement without explanation.\n"
            "- Wrap the final query between `[SQL]` and `[/SQL]` markers.\n\n"
            "### Answer\n"
            f"Given the database schema, here is the SQL query that [QUESTION]{question}[/QUESTION]\n"
            "[SQL]\n"
        )

    def _build_sqlcoder_refine_prompt(self, question: str, previous_sql: str, error_message: str) -> str:
        schema_section = ""
        if self.schema_text:
            schema_section = (
                "### Database Schema\n"
                f"{self.schema_text.strip()}\n\n"
            )

        return (
            "### Task\n"
            f"Refine the SQL for [QUESTION]{question}[/QUESTION] so it runs on Google BigQuery.\n\n"
            f"{schema_section}"
            "### Previous SQL\n"
            f"```sql\n{previous_sql.strip()}\n```\n\n"
            "### BigQuery Error\n"
            f"{error_message.strip()}\n\n"
            "### Requirements\n"
            "- Keep a single BigQuery statement using only `physionet-data.mimiciv_3_1_hosp` and `physionet-data.mimiciv_3_1_icu`.\n"
            "- Apply the minimal fix for the error.\n"
            "- Output only the corrected query wrapped in `[SQL]` and `[/SQL]`.\n\n"
            "### Answer\n"
            "[SQL]\n"
        )

    def generate_sql(self, question: str) -> str:
        """Generate SQL query using a vLLM-hosted model (CoT format)."""
        prompt = self._build_generation_prompt(question)
        return self._run_llm(prompt)

    def _generate_sql_local_batch(self, prompts: List[str]) -> List[str]:
        """Generate SQL for a list of prompts using the local vLLM engine."""
        if not prompts:
            return []

        if not self._ensure_local_engine():
            logging.warning("vLLM local engine is not initialised; falling back to sequential generation.")
            return [self._run_llm(prompt) for prompt in prompts]

        results: List[str] = []
        chunk_size = max(1, self.batch_size)
        for start in range(0, len(prompts), chunk_size):
            chunk = prompts[start : start + chunk_size]
            try:
                batch_outputs = self.llm.generate(chunk, self.sampling_params)
            except Exception as exc:
                logging.warning(
                    "vLLM batch generation failed for prompts %d..%d (%s); falling back to per-prompt generation.",
                    start,
                    start + len(chunk) - 1,
                    exc,
                )
                results.extend(self._run_llm(prompt) for prompt in chunk)
                continue

            if len(batch_outputs) != len(chunk):
                logging.warning(
                    "vLLM batch generation returned %d outputs for %d prompts; retrying sequentially for that chunk.",
                    len(batch_outputs),
                    len(chunk),
                )
                results.extend(self._run_llm(prompt) for prompt in chunk)
                continue

            for local_idx, prompt in enumerate(chunk):
                candidate = batch_outputs[local_idx]
                text = ""
                if getattr(candidate, "outputs", None):
                    first_output = candidate.outputs[0]
                    text = getattr(first_output, "text", "") or ""
                if not text:
                    logging.debug("Empty batch output received; invoking per-prompt fallback.")
                    results.append(self._run_llm(prompt))
                else:
                    results.append(clean_sql_response(text.strip()))

        return results

    @property
    def supports_batch_generation(self) -> bool:
        return self.batch_enabled

    def _ensure_ray_initialised(self) -> None:
        if not self.batch_enabled or self._ray is None or self._ray_initialized:
            return
        init_kwargs = dict(self.ray_init_kwargs)
        if self.ray_address and "address" not in init_kwargs:
            init_kwargs["address"] = self.ray_address
        if self.ray_namespace and "namespace" not in init_kwargs:
            init_kwargs["namespace"] = self.ray_namespace
        init_kwargs.setdefault("ignore_reinit_error", True)
        self._ray.init(**init_kwargs)
        self._ray_initialized = True

    def generate_sql_batch(self, questions: List[str]) -> List[str]:
        """Generate SQL for a batch of questions, optionally using Ray Data."""
        prompts = [self._build_generation_prompt(question) for question in questions]
        if not prompts:
            return []

        if self.use_server_backend or not self.batch_enabled:
            return [self._run_llm(prompt) for prompt in prompts]

        if not self.ray_enabled or self._ray is None:
            return self._generate_sql_local_batch(prompts)

        try:
            self._ensure_ray_initialised()
            ray = self._ray
            items = [{"idx": idx, "prompt": prompt} for idx, prompt in enumerate(prompts)]
            ds = ray.data.from_items(items)

            engine_kwargs = dict(self.batch_engine_kwargs)
            engine_kwargs.setdefault("max_num_batched_tokens", self.max_num_batched_tokens)

            processor_config = self._vllm_processor_config_cls(
                model_source=self.model_id,
                engine_kwargs=engine_kwargs,
                concurrency=self.batch_concurrency,
                batch_size=self.batch_size,
            )
            sampling_dict = self.sampling_config.to_dict()

            processor = self._build_llm_processor(
                processor_config,
                preprocess=lambda row: dict(
                    prompt=row["prompt"],
                    sampling_params=sampling_dict,
                ),
                postprocess=lambda row: {
                    **row,
                    "generated_text": clean_sql_response(row.get("generated_text", "")),
                },
            )

            ds = processor(ds)
            ds = ds.sort("idx")
            outputs = ds.take_all()
            return [row.get("generated_text", "") for row in outputs]
        except Exception as exc:  # pragma: no cover - Ray runtime issues
            logging.warning("Ray batch inference failed (%s); falling back to local batch generation.", exc)
            ray_module = self._ray
            self._ray = None
            self._ray_initialized = False
            self.ray_enabled = False
            if ray_module is not None:
                try:
                    ray_module.shutdown()
                except Exception:
                    logging.debug("Ray shutdown raised an exception.", exc_info=True)
            return self._generate_sql_local_batch(prompts)

    def refine_sql(self, question: str, previous_sql: str, error_message: str) -> str:
        """Refine a failing SQL query by querying the vLLM-hosted model."""
        prompt = self._build_refine_prompt(question, previous_sql, error_message)
        return self._run_llm(prompt)


class SQLExecutor:
    """Execute SQL queries using BigQuery with optional self-refinement support."""

    def __init__(self, model_name: str, project_id: Optional[str] = None):
        self.model_name = model_name
        resolved_project_id = project_id or os.environ.get("BIGQUERY_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")
        if not resolved_project_id:
            raise ValueError(
                "BigQuery project ID is required. Pass --bigquery-project or set "
                "GOOGLE_CLOUD_PROJECT / BIGQUERY_PROJECT in the environment."
            )
        self.project_id = resolved_project_id
        self.bigquery_client = bigquery.Client(project=self.project_id)
        self.max_bytes_billed = 50 * 1024 * 1024 * 1024  # 50GB
        self.query_timeout_seconds = 300

    def execute_sql(self, sql: str) -> Tuple[bool, Optional[pd.DataFrame], Optional[str]]:
        """Execute SQL on BigQuery"""
        return self._execute_sql(sql)

    def _execute_sql(self, sql: str) -> Tuple[bool, Optional[pd.DataFrame], Optional[str]]:
        """Execute SQL on BigQuery"""
        try:
            job_config = bigquery.QueryJobConfig(
                use_query_cache=True,
                maximum_bytes_billed=self.max_bytes_billed
            )
            
            query_job = self.bigquery_client.query(sql, job_config=job_config)
            results = query_job.result(timeout=self.query_timeout_seconds)
            df = results.to_dataframe()
            
            return True, df, None
            
        except Exception as e:
            error_str = str(e)
            logging.error(f"SQL execution failed: {error_str}")
            return False, None, error_str


class ClinicalBenchmarkTester:
    """Main class for testing LLM text-to-SQL ability on clinical benchmark data"""
    
    def __init__(
        self,
        model_alias: str,
        *,
        model_id_override: Optional[str] = None,
        tokenizer_id: Optional[str] = None,
        revision: Optional[str] = None,
        dtype: Optional[str] = None,
        tensor_parallel_size: Optional[int] = None,
        trust_remote_code: Optional[bool] = None,
        download_dir: Optional[str] = None,
        gpu_memory_utilization: Optional[float] = None,
        max_model_len: Optional[int] = None,
        temperature: float = 0.2,
        top_p: float = 0.9,
        top_k: int = -1,
        max_new_tokens: int = 1024,
        stop_sequences: Optional[List[str]] = None,
        data_root: Optional[Path] = None,
        output_root: Optional[Path] = None,
        bigquery_project: Optional[str] = None,
        max_refinement_attempts: int = 2,
        enforce_eager: Optional[bool] = None,
        server_url: Optional[str] = None,
        server_api_key: Optional[str] = None,
        server_model: Optional[str] = None,
        enable_batch_inference: bool = False,
        batch_size: Optional[int] = None,
        batch_concurrency: Optional[int] = None,
        max_num_batched_tokens: Optional[int] = None,
        ray_address: Optional[str] = None,
        ray_namespace: Optional[str] = None,
        ray_init_kwargs: Optional[Dict[str, Any]] = None,
    ):
        try:
            canonical_alias, spec = resolve_open_source_model_alias(model_alias)
        except KeyError as exc:
            raise ValueError(
                f"Model '{model_alias}' is not supported. "
                f"Choose from: {', '.join(SUPPORTED_OPEN_SOURCE_MODELS)}"
            ) from exc

        self.requested_model_alias = model_alias
        self.model_alias = canonical_alias
        self.model_name = _sanitize_model_alias(self.model_alias)
        self.max_refinement_attempts = max_refinement_attempts

        self.sql_generator = VLLMSQLGenerator(
            model_alias=self.model_alias,
            spec=spec,
            model_id_override=model_id_override,
            tokenizer_id=tokenizer_id,
            revision=revision,
            dtype=dtype,
            tensor_parallel_size=tensor_parallel_size,
            trust_remote_code=trust_remote_code,
            download_dir=download_dir,
            gpu_memory_utilization=gpu_memory_utilization,
            max_model_len=max_model_len,
            temperature=temperature,
            top_p=top_p,
            top_k=top_k,
            max_new_tokens=max_new_tokens,
            stop_sequences=stop_sequences,
            enforce_eager=enforce_eager,
            server_url=server_url,
            server_api_key=server_api_key,
            server_model=server_model,
            enable_batch_inference=enable_batch_inference,
            batch_size=batch_size,
            batch_concurrency=batch_concurrency,
            max_num_batched_tokens=max_num_batched_tokens,
            ray_address=ray_address,
            ray_namespace=ray_namespace,
            ray_init_kwargs=ray_init_kwargs,
        )
        self.model_id = self.sql_generator.model_id
        if self.requested_model_alias != self.model_alias:
            logging.info(
                "Normalised model alias '%s' to canonical name '%s'.",
                self.requested_model_alias,
                self.model_alias,
            )

        project_id = bigquery_project or os.environ.get("BIGQUERY_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")
        self.sql_executor = SQLExecutor(self.model_name, project_id=project_id)
        
        # Paths: resolve repo root so benchmark/data live under current project
        # This file sits in model_inference/, so parent.parent is the repo root
        self.base_path = Path(__file__).resolve().parent.parent
        data_root_path = Path(data_root) if data_root else (self.base_path / "data")
        self.data_root = data_root_path
        self.benchmark_path = self.data_root / "benchmark"
        self.benchmark_split_path = self.data_root / "splits"
        if not self.benchmark_split_path.exists():
            raise FileNotFoundError(f"Benchmark splits not found at {self.benchmark_split_path}")
        if not self.benchmark_path.exists():
            raise FileNotFoundError(f"Benchmark data not found at {self.benchmark_path}")
        # Save CoT outputs under the unified outputs directory
        default_output_root = self.base_path / "outputs" / "inference"
        self.output_path = Path(output_root) if output_root else default_output_root
        self.output_path.mkdir(parents=True, exist_ok=True)
        
        # Benchmark configuration
        self.domains = list(BENCHMARK_DOMAINS)
        self.difficulty_levels = list(BENCHMARK_DIFFICULTIES)
        self.splits = list(BENCHMARK_SPLITS)
        
        # Setup logging
        logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
        self.logger = logging.getLogger(__name__)
        self.logger.info("Benchmark splits: %s", self.benchmark_split_path)
        self.logger.info("Writing outputs to: %s", self.output_path)
        self.logger.info("BigQuery project: %s", self.sql_executor.project_id)
        self.logger.info("Model checkpoint: %s", self.model_id)
        if server_url:
            self.logger.info("OpenAI-compatible server URL: %s", server_url)
        if self.sql_generator.supports_batch_generation:
            if self.sql_generator.ray_enabled:
                self.logger.info(
                    "Ray Data batch inference enabled (batch_size=%s, concurrency=%s)",
                    self.sql_generator.batch_size,
                    self.sql_generator.batch_concurrency,
                )
            else:
                self.logger.info(
                    "Local batch inference enabled (chunk_size=%s)",
                    self.sql_generator.batch_size,
                )
    
    def get_benchmark_queries(self, split: str, domain: str, difficulty: str) -> List[Path]:
        """Get all benchmark query files for a split, domain and difficulty level"""
        # Prefer split paths: data/splits/{split}/{domain}/{difficulty}
        query_dir = self.benchmark_split_path / split / domain / difficulty
        query_files = []
        
        if query_dir.exists():
            for folder in sorted(query_dir.iterdir()):
                if folder.is_dir():
                    query_file = folder / f"query_{folder.name}.txt"
                    if query_file.exists():
                        query_files.append(query_file)
        
        return query_files
    
    def process_single_query(
        self,
        query_file: Path,
        domain: str,
        difficulty: str,
        *,
        question_override: Optional[str] = None,
        initial_sql: Optional[str] = None,
    ) -> Dict:
        """Process a single benchmark query with self-refinement attempts."""
        try:
            # Read query
            if question_override is not None:
                question = question_override.strip()
            else:
                with open(query_file, 'r', encoding='utf-8') as f:
                    question = f.read().strip()

            self.logger.info(f"Processing: {query_file.parent.name} - {question[:80]}...")

            attempts: List[Dict] = []

            # Initial SQL generation
            sql = initial_sql.strip() if isinstance(initial_sql, str) else self.sql_generator.generate_sql(question)
            if not sql:
                return {
                    "success": False,
                    "error": "Failed to generate SQL",
                    "question": question,
                    "sql": "",
                    "results_df": None,
                    "row_count": 0,
                    "attempts": attempts,
                }

            # Attempt 1 execution
            success, df, error = self.sql_executor.execute_sql(sql)
            row_count = len(df) if (success and df is not None) else 0
            attempts.append({
                "attempt": 1,
                "sql": sql,
                "success": success,
                "error": None if success else error,
                "row_count": row_count,
            })

            # Refinement loop if needed
            attempt_num = 1
            while not success and attempt_num < 1 + self.max_refinement_attempts:
                refine_err = error or "Execution failed"
                refined_sql = self.sql_generator.refine_sql(question, sql, refine_err)
                if not refined_sql:
                    # Could not refine; break
                    break
                sql = refined_sql
                attempt_num += 1
                success, df, error = self.sql_executor.execute_sql(sql)
                row_count = len(df) if (success and df is not None) else 0
                attempts.append({
                    "attempt": attempt_num,
                    "sql": sql,
                    "success": success,
                    "error": None if success else error,
                    "row_count": row_count,
                })

                if success:
                    break

            return {
                "success": success,
                "question": question,
                "sql": sql if success or sql else "",
                "results_df": df if success else None,
                "error": None if success else error,
                "row_count": row_count if success else 0,
                "attempts": attempts,
            }

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "question": "",
                "sql": "",
                "results_df": None,
                "row_count": 0,
                "attempts": [],
            }
    
    def copy_rubric_trees(self, source_query_dir: Path, output_dir: Path):
        """Copy rubric tree files from benchmark to output directory"""
        rubric_files = ["results_rubric_tree.json", "sql_rubric_tree.json"]
        
        for rubric_file in rubric_files:
            source_file = source_query_dir / rubric_file
            if source_file.exists():
                target_file = output_dir / rubric_file
                shutil.copy2(source_file, target_file)
    
    def save_results(self, result: Dict, query_file: Path, split: str, domain: str, difficulty: str):
        """Save results to experiments directory structure, including refinement attempts metadata"""
        folder_name = query_file.parent.name  # e.g., "001"
        
        # Create output directory including split to avoid collisions:
        # outputs/inference/{model_name}/{split}/{domain}/{difficulty}/{query_number}/
        output_dir = self.output_path / self.model_name / split / domain / difficulty / folder_name
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Save query
        query_output = output_dir / f"query_{folder_name}.txt"
        with open(query_output, 'w', encoding='utf-8') as f:
            f.write(result.get("question", ""))
        
        # Save final generated SQL (if any)
        sql_output = output_dir / f"sql_{folder_name}.sql"
        with open(sql_output, 'w', encoding='utf-8') as f:
            sql_content = result.get("sql", "")
            if result.get("error") and not sql_content:
                sql_content = f"-- SQL Generation Failed: {result['error']}\n"
            f.write(sql_content)

        # Attempts metadata (do not save per-attempt SQL files)
        attempts = result.get("attempts", [])
        
        # Save execution results
        csv_output = output_dir / f"result_{folder_name}.csv"
        if result["results_df"] is not None and len(result["results_df"]) > 0:
            result["results_df"].to_csv(csv_output, index=False)
        else:
            # Create empty CSV with null result
            pd.DataFrame({"result": [None]}).to_csv(csv_output, index=False)
        
        # Copy rubric trees from benchmark
        source_query_dir = query_file.parent
        self.copy_rubric_trees(source_query_dir, output_dir)
        
        # Save detailed execution summary (with refinement attempts)
        summary = {
            "query": result.get("question", ""),
            "final_sql": result.get("sql", ""),
            "execution_success": result.get("success", False),
            "row_count": result.get("row_count", 0),
            "final_error": result.get("error"),
            "model": self.model_name,
            "model_id": self.model_id,
            "refinement_attempts": [
                {
                    "attempt": a.get("attempt"),
                    "success": a.get("success"),
                    "row_count": a.get("row_count", 0),
                    "error": a.get("error"),
                }
                for a in attempts
            ],
        }
        
        summary_output = output_dir / "execution_summary.json"
        with open(summary_output, 'w', encoding='utf-8') as f:
            json.dump(summary, f, indent=2, default=str)
        
        self.logger.info(f"Results saved to: {output_dir}")
    
    def test_domain_difficulty(self, split: str, domain: str, difficulty: str, max_queries: Optional[int] = None):
        """Test all queries in a split, domain and difficulty level"""
        self.logger.info(f"Testing [{split}] {domain} - {difficulty}")
        
        query_files = self.get_benchmark_queries(split, domain, difficulty)
        if max_queries:
            query_files = query_files[:max_queries]
        
        self.logger.info(f"Found {len(query_files)} queries to test")
        
        results_summary = {
            "total": len(query_files),
            "successful": 0,
            "failed": 0,
            "split": split,
            "domain": domain,
            "difficulty": difficulty,
            "model": self.model_name,
            "model_id": self.model_id,
        }
        
        # Track attempt-wise success counts (per-round execution)
        num_attempts = 1 + self.max_refinement_attempts
        attempt_success_counts = {i: 0 for i in range(1, num_attempts + 1)}

        question_cache: Dict[Path, str] = {}
        initial_sql_map: Dict[Path, str] = {}
        if query_files and self.sql_generator.supports_batch_generation:
            self.logger.info("Preparing batch prompts for %d queries", len(query_files))
            for query_file in query_files:
                with open(query_file, 'r', encoding='utf-8') as f:
                    question_cache[query_file] = f.read().strip()

            batch_questions = [question_cache[qf] for qf in query_files]
            try:
                batch_sql = self.sql_generator.generate_sql_batch(batch_questions)
            except Exception as exc:  # pragma: no cover - defensive
                self.logger.warning("Batch generation failed with error %s; falling back to sequential mode.", exc)
                batch_sql = []

            if len(batch_sql) == len(query_files):
                for qf, sql in zip(query_files, batch_sql):
                    initial_sql_map[qf] = sql
            else:
                self.logger.warning(
                    "Batch generation returned %d outputs for %d queries; falling back to per-query generation.",
                    len(batch_sql),
                    len(query_files),
                )
                # Clear caches to trigger sequential path for mismatched runs
                question_cache.clear()
                initial_sql_map.clear()

        for i, query_file in enumerate(query_files, 1):
            self.logger.info(f"Query {i}/{len(query_files)}")
            question_override = question_cache.get(query_file)
            initial_sql = initial_sql_map.get(query_file)

            result = self.process_single_query(
                query_file,
                domain,
                difficulty,
                question_override=question_override,
                initial_sql=initial_sql,
            )
            
            if result["success"]:
                results_summary["successful"] += 1
                self.logger.info("✓ Success")
                # Attribute success to the earliest successful attempt
                first_success_attempt = None
                for att in result.get("attempts", []):
                    if att.get("success"):
                        first_success_attempt = att.get("attempt")
                        break
                if isinstance(first_success_attempt, int) and 1 <= first_success_attempt <= num_attempts:
                    attempt_success_counts[first_success_attempt] += 1
            else:
                results_summary["failed"] += 1
                self.logger.warning(f"✗ Failed: {result['error']}")
            
            # Save results
            self.save_results(result, query_file, split, domain, difficulty)
            
            # Minimal pause between queries
            time.sleep(0.1)
        
        success_rate = results_summary['successful']/results_summary['total']*100 if results_summary['total'] > 0 else 0
        self.logger.info(f"[{split}] {domain} - {difficulty} Summary: {results_summary['successful']}/{results_summary['total']} ({success_rate:.1f}%)")
        
        # Compute and log per‑attempt and cumulative execution success
        if results_summary['total'] > 0:
            parts = []
            cum_parts = []
            running = 0
            for a in range(1, num_attempts + 1):
                cnt = attempt_success_counts.get(a, 0)
                rate = (cnt / results_summary['total']) * 100
                parts.append(f"Attempt {a}: {cnt}/{results_summary['total']} ({rate:.1f}%)")
                running += cnt
                cum_parts.append(f"≤ Attempt {a}: {running}/{results_summary['total']} ({(running / results_summary['total']) * 100:.1f}%)")
            self.logger.info("Per‑attempt execution success: " + "; ".join(parts))
            self.logger.info("Cumulative success by attempt: " + "; ".join(cum_parts))
        
        # Attach attempt-wise metrics to the returned summary
        results_summary["attempt_success_counts"] = attempt_success_counts
        if results_summary['total'] > 0:
            results_summary["attempt_success_rates"] = {k: (v / results_summary['total']) * 100 for k, v in attempt_success_counts.items()}
            acc = 0
            cum_counts = {}
            for k in range(1, num_attempts + 1):
                acc += attempt_success_counts.get(k, 0)
                cum_counts[k] = acc
            results_summary["attempt_cumulative_success_counts"] = cum_counts
            results_summary["attempt_cumulative_success_rates"] = {k: (v / results_summary['total']) * 100 for k, v in cum_counts.items()}
        else:
            results_summary["attempt_success_rates"] = {k: 0.0 for k in attempt_success_counts}
            results_summary["attempt_cumulative_success_counts"] = {k: 0 for k in attempt_success_counts}
            results_summary["attempt_cumulative_success_rates"] = {k: 0.0 for k in attempt_success_counts}
        
        return results_summary
    
    def run_benchmark_test(self, domains: Optional[List[str]] = None, 
                          difficulties: Optional[List[str]] = None,
                          max_queries_per_level: Optional[int] = None,
                          splits: Optional[List[str]] = None):
        """Run benchmark tests for specified splits, domains, and difficulties"""
        test_domains = domains if domains else self.domains
        test_difficulties = difficulties if difficulties else self.difficulty_levels
        test_splits = splits if splits else self.splits
        
        self.logger.info(
            "Starting Clinical Benchmark Testing for model alias '%s' (id: %s)",
            self.model_name,
            self.model_id,
        )
        
        num_attempts = 1 + self.max_refinement_attempts

        overall_summary = {
            "model": self.model_name,
            "model_id": self.model_id,
            "splits": {},
            "total_queries": 0,
            "total_successful": 0,
            "attempt_success_counts": {i: 0 for i in range(1, num_attempts + 1)},
            "attempt_success_rates": {},
            "attempt_cumulative_success_counts": {},
            "attempt_cumulative_success_rates": {},
        }
        
        for split in test_splits:
            split_summary = {
                "total_queries": 0,
                "total_successful": 0,
                "domain_results": {},
                "attempt_success_counts": {i: 0 for i in range(1, num_attempts + 1)},
                "attempt_success_rates": {},
                "attempt_cumulative_success_counts": {},
                "attempt_cumulative_success_rates": {},
            }
            for domain in test_domains:
                domain_summary = {
                    "total_queries": 0,
                    "total_successful": 0,
                    "level_results": {},
                    "attempt_success_counts": {i: 0 for i in range(1, num_attempts + 1)},
                    "attempt_success_rates": {},
                    "attempt_cumulative_success_counts": {},
                    "attempt_cumulative_success_rates": {},
                }
                for difficulty in test_difficulties:
                    level_summary = self.test_domain_difficulty(split, domain, difficulty, max_queries_per_level)
                    domain_summary["total_queries"] += level_summary["total"]
                    domain_summary["total_successful"] += level_summary["successful"]
                    domain_summary["level_results"][difficulty] = level_summary
                    # Aggregate attempt-wise counts into domain
                    lvl_counts = level_summary.get("attempt_success_counts", {})
                    for a in range(1, num_attempts + 1):
                        domain_summary["attempt_success_counts"][a] += int(lvl_counts.get(a, 0))
                # Compute domain-level rates
                tq = domain_summary["total_queries"] or 0
                if tq > 0:
                    domain_summary["attempt_success_rates"] = {a: (domain_summary["attempt_success_counts"][a] / tq) * 100 for a in range(1, num_attempts + 1)}
                    acc = 0
                    cum_counts = {}
                    for a in range(1, num_attempts + 1):
                        acc += domain_summary["attempt_success_counts"][a]
                        cum_counts[a] = acc
                    domain_summary["attempt_cumulative_success_counts"] = cum_counts
                    domain_summary["attempt_cumulative_success_rates"] = {a: (cum_counts[a] / tq) * 100 for a in range(1, num_attempts + 1)}
                # Add domain counts into split aggregate
                for a in range(1, num_attempts + 1):
                    split_summary["attempt_success_counts"][a] += domain_summary["attempt_success_counts"][a]
                split_summary["total_queries"] += domain_summary["total_queries"]
                split_summary["total_successful"] += domain_summary["total_successful"]
                split_summary["domain_results"][domain] = domain_summary
            # Compute split-level attempt metrics
            stq = split_summary["total_queries"] or 0
            if stq > 0:
                split_summary["attempt_success_rates"] = {a: (split_summary["attempt_success_counts"][a] / stq) * 100 for a in range(1, num_attempts + 1)}
                acc = 0
                scum_counts = {}
                for a in range(1, num_attempts + 1):
                    acc += split_summary["attempt_success_counts"][a]
                    scum_counts[a] = acc
                split_summary["attempt_cumulative_success_counts"] = scum_counts
                split_summary["attempt_cumulative_success_rates"] = {a: (scum_counts[a] / stq) * 100 for a in range(1, num_attempts + 1)}
                # Log split-level attempt success summary
                parts = [f"Attempt {a}: {split_summary['attempt_success_counts'][a]}/{stq} ({split_summary['attempt_success_rates'][a]:.1f}%)" for a in range(1, num_attempts + 1)]
                self.logger.info(f"[{split}] Per‑attempt execution success: " + "; ".join(parts))
                cparts = [f"≤ Attempt {a}: {split_summary['attempt_cumulative_success_counts'][a]}/{stq} ({split_summary['attempt_cumulative_success_rates'][a]:.1f}%)" for a in range(1, num_attempts + 1)]
                self.logger.info(f"[{split}] Cumulative success by attempt: " + "; ".join(cparts))
            overall_summary["splits"][split] = split_summary
            overall_summary["total_queries"] += split_summary["total_queries"]
            overall_summary["total_successful"] += split_summary["total_successful"]
            for a in range(1, num_attempts + 1):
                overall_summary["attempt_success_counts"][a] += split_summary["attempt_success_counts"][a]
        
        # Save overall summary
        summary_file = self.output_path / self.model_name / "benchmark_summary.json"
        summary_file.parent.mkdir(parents=True, exist_ok=True)
        # Compute overall attempt metrics and log
        otq = overall_summary["total_queries"] or 0
        if otq > 0:
            overall_summary["attempt_success_rates"] = {a: (overall_summary["attempt_success_counts"][a] / otq) * 100 for a in range(1, num_attempts + 1)}
            acc = 0
            ocum_counts = {}
            for a in range(1, num_attempts + 1):
                acc += overall_summary["attempt_success_counts"][a]
                ocum_counts[a] = acc
            overall_summary["attempt_cumulative_success_counts"] = ocum_counts
            overall_summary["attempt_cumulative_success_rates"] = {a: (ocum_counts[a] / otq) * 100 for a in range(1, num_attempts + 1)}
            # Log
            oparts = [f"Attempt {a}: {overall_summary['attempt_success_counts'][a]}/{otq} ({overall_summary['attempt_success_rates'][a]:.1f}%)" for a in range(1, num_attempts + 1)]
            self.logger.info("[OVERALL] Per‑attempt execution success: " + "; ".join(oparts))
            ocparts = [f"≤ Attempt {a}: {overall_summary['attempt_cumulative_success_counts'][a]}/{otq} ({overall_summary['attempt_cumulative_success_rates'][a]:.1f}%)" for a in range(1, num_attempts + 1)]
            self.logger.info("[OVERALL] Cumulative success by attempt: " + "; ".join(ocparts))
        with open(summary_file, 'w', encoding='utf-8') as f:
            json.dump(overall_summary, f, indent=2, default=str)
        
        # Print final summary
        total_queries = overall_summary['total_queries']
        total_successful = overall_summary['total_successful']
        overall_rate = total_successful/total_queries*100 if total_queries > 0 else 0
        
        self.logger.info("=" * 60)
        self.logger.info(
            "BENCHMARK TESTING COMPLETE - %s (id: %s)",
            self.model_name,
            self.model_id,
        )
        self.logger.info(f"Total Queries (all splits): {total_queries}")
        self.logger.info(f"Total Successful (all splits): {total_successful}")
        self.logger.info(f"Overall Success Rate: {overall_rate:.1f}%")
        self.logger.info(f"Results saved to: {self.output_path / self.model_name}")
        self.logger.info("=" * 60)
        
        return overall_summary


def test_multiple_models(
    model_names: List[str],
    domains: Optional[List[str]] = None,
    difficulties: Optional[List[str]] = None,
    max_queries_per_level: Optional[int] = None,
    splits: Optional[List[str]] = None,
    tester_kwargs: Optional[Dict[str, Any]] = None,
):
    """Test multiple models on the clinical benchmark"""
    all_results = {}
    tester_kwargs = tester_kwargs or {}
    
    for model_name in model_names:
        print(f"\n{'='*60}")
        print(f"TESTING MODEL: {model_name}")
        print(f"{'='*60}")
        
        tester = ClinicalBenchmarkTester(model_alias=model_name, **tester_kwargs)
        model_results = tester.run_benchmark_test(
            domains=domains,
            difficulties=difficulties, 
            max_queries_per_level=max_queries_per_level,
            splits=splits,
        )
        all_results[model_name] = model_results
    
    return all_results


def run_single_model_experiment(
    model_name: str,
    domains: Optional[List[str]] = None,
    difficulties: Optional[List[str]] = None,
    max_queries_per_level: Optional[int] = None,
    splits: Optional[List[str]] = None,
    tester_kwargs: Optional[Dict[str, Any]] = None,
):
    """Run benchmark test for a single model with flexible configuration"""
    tester = ClinicalBenchmarkTester(model_alias=model_name, **(tester_kwargs or {}))
    return tester.run_benchmark_test(
        domains=domains,
        difficulties=difficulties,
        max_queries_per_level=max_queries_per_level,
        splits=splits,
    )

def run_multi_model_experiment(
    model_names: List[str],
    domains: Optional[List[str]] = None,
    difficulties: Optional[List[str]] = None,
    max_queries_per_level: Optional[int] = None,
    splits: Optional[List[str]] = None,
    tester_kwargs: Optional[Dict[str, Any]] = None,
):
    """Run benchmark test for multiple models with flexible configuration"""
    return test_multiple_models(
        model_names=model_names,
        domains=domains,
        difficulties=difficulties,
        max_queries_per_level=max_queries_per_level,
        splits=splits,
        tester_kwargs=tester_kwargs
    )

def run_domain_comparison_experiment(
    domain: str,
    model_names: List[str],
    max_queries_per_level: Optional[int] = None,
    splits: Optional[List[str]] = None,
    tester_kwargs: Optional[Dict[str, Any]] = None,
):
    """Compare multiple models on a specific domain"""
    results = {}
    tester_kwargs = tester_kwargs or {}
    for model_name in model_names:
        print(f"\nTesting {model_name} on {domain}...")
        tester = ClinicalBenchmarkTester(model_alias=model_name, **tester_kwargs)
        results[model_name] = tester.run_benchmark_test(
            domains=[domain],
            max_queries_per_level=max_queries_per_level,
            splits=splits,
        )
    return results


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    supported_models_display = ", ".join(SUPPORTED_OPEN_SOURCE_MODELS)
    available_domains = [
        "Diagnostic_Procedures",
        "Disease_Diagnosis_and_Outcomes",
        "Laboratory_Results_Analysis",
        "Medication_Management",
        "Patient_Demographics_and_Admissions",
        "Vital_Signs_Monitoring",
    ]
    available_difficulties = ["easy_level_queries", "medium_level_queries", "hard_level_queries"]
    available_splits = list(BENCHMARK_SPLITS)

    parser = argparse.ArgumentParser(
        description="Clinical SQL Benchmark Evaluator for vLLM-hosted open-source models.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Evaluate DeepSeek-R1 on easy test queries\n"
            "  python clinical_sql_benchmark_evaluator_vllm.py --model DeepSeek-R1 \\\n"
            "      --domain Diagnostic_Procedures --difficulties easy_level_queries\n\n"
            "  # Evaluate MedGemma-27B on the full test split across all domains\n"
            "  python clinical_sql_benchmark_evaluator_vllm.py --model MedGemma-27B\n\n"
            "  # Sweep multiple models with shared decoding settings\n"
            "  python clinical_sql_benchmark_evaluator_vllm.py --models "
            "DeepSeek-R1 SQLCoder-7B-2 "
            "--max-queries 25\n"
        ),
    )

    model_group = parser.add_mutually_exclusive_group(required=True)
    model_group.add_argument(
        "--model",
        choices=SUPPORTED_OPEN_SOURCE_MODELS,
        help=(
            "Single open-source model alias to evaluate. "
            f"Supported in the paper: {supported_models_display}"
        ),
    )
    model_group.add_argument(
        "--models",
        nargs="+",
        choices=SUPPORTED_OPEN_SOURCE_MODELS,
        help=(
            "Evaluate multiple models sequentially (each loaded via vLLM). "
            f"Supported in the paper: {supported_models_display}"
        ),
    )

    parser.add_argument(
        "--model-id-override",
        help=(
            "Optional HuggingFace ID or local path to override the default checkpoint "
            "associated with the selected model alias."
        ),
    )
    parser.add_argument(
        "--tokenizer",
        help="Tokenizer repo ID or path if different from --model.",
    )
    parser.add_argument(
        "--revision",
        help="Model revision or git commit to pull from HuggingFace.",
    )
    parser.add_argument(
        "--download-dir",
        help="Directory to cache model weights locally.",
    )
    parser.add_argument(
        "--tensor-parallel-size",
        type=int,
        help="Tensor parallelism degree for vLLM (overrides the spec default).",
    )
    parser.add_argument(
        "--gpu-memory-utilization",
        type=float,
        help="Fraction of GPU memory to allocate for the model (overrides the spec default).",
    )
    parser.add_argument(
        "--dtype",
        help="Model weights dtype (auto, float16, bfloat16, float32). Overrides the spec default.",
    )
    parser.add_argument(
        "--max-model-len",
        type=int,
        help="Override maximum sequence length when loading the model.",
    )
    trust_group = parser.add_mutually_exclusive_group()
    trust_group.add_argument(
        "--trust-remote-code",
        dest="trust_remote_code",
        action="store_true",
        help="Force-enable trust_remote_code when loading the model.",
    )
    trust_group.add_argument(
        "--no-trust-remote-code",
        dest="trust_remote_code",
        action="store_false",
        help="Force-disable trust_remote_code when loading the model.",
    )
    parser.set_defaults(trust_remote_code=None)
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.2,
        help="Sampling temperature for generation (default: 0.2).",
    )
    parser.add_argument(
        "--top-p",
        type=float,
        default=0.9,
        help="Top-p nucleus sampling parameter (default: 0.9).",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=-1,
        help="Top-k sampling parameter (-1 disables top-k, default).",
    )
    parser.add_argument(
        "--max-new-tokens",
        type=int,
        default=32768,
        help="Maximum number of new tokens to sample (default: 32768).",
    )
    parser.add_argument(
        "--stop-sequences",
        nargs="+",
        metavar="STR",
        help="Optional additional stop sequences passed to vLLM.",
    )
    parser.add_argument(
        "--vllm-server-url",
        help="Base URL of an OpenAI-compatible vLLM server (enables server-backed inference).",
    )
    parser.add_argument(
        "--vllm-server-api-key",
        help="API key for the OpenAI-compatible vLLM server (default: VLLM_SERVER_API_KEY env).",
    )
    parser.add_argument(
        "--vllm-server-model",
        help="Model name to request from the vLLM server (defaults to the pipeline model alias mapping).",
    )
    parser.add_argument(
        "--enable-batch-inference",
        action="store_true",
        help="Enable Ray Data batch inference pipeline for initial SQL generation.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        help="Batch size for Ray Data vLLM processor.",
    )
    parser.add_argument(
        "--batch-concurrency",
        type=int,
        help="Number of parallel vLLM replicas to launch for Ray Data batch inference.",
    )
    parser.add_argument(
        "--max-num-batched-tokens",
        type=int,
        help="Maximum number of batched tokens when using Ray Data batch inference.",
    )
    parser.add_argument(
        "--ray-address",
        help="Ray cluster address to connect to for batch inference.",
    )
    parser.add_argument(
        "--ray-namespace",
        help="Ray namespace to use when initialising batch inference sessions.",
    )
    parser.add_argument(
        "--ray-init-kwargs",
        help="JSON dictionary of additional arguments passed to ray.init when batch inference is enabled.",
    )

    domain_group = parser.add_mutually_exclusive_group()
    domain_group.add_argument(
        "--domain",
        choices=available_domains,
        help="Single clinical domain to evaluate.",
    )
    domain_group.add_argument(
        "--domains",
        nargs="+",
        choices=available_domains,
        help="Multiple clinical domains to evaluate (default: all).",
    )

    parser.add_argument(
        "--difficulties",
        nargs="+",
        choices=available_difficulties,
        help="Difficulty levels to evaluate (default: all).",
    )
    parser.add_argument(
        "--max-queries",
        type=int,
        help="Maximum number of queries per difficulty level (default: all).",
    )
    split_group = parser.add_mutually_exclusive_group()
    split_group.add_argument(
        "--split",
        choices=available_splits,
        help="Single benchmark split to evaluate (default: all).",
    )
    split_group.add_argument(
        "--splits",
        nargs="+",
        choices=available_splits,
        help="Benchmark splits to evaluate (default: test and validation).",
    )
    parser.add_argument(
        "--data-root",
        type=Path,
        help="Path to the CLINSQL data directory (default: repo data/).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Directory for inference outputs (default: outputs/inference).",
    )
    parser.add_argument(
        "--bigquery-project",
        help="Google Cloud project ID for BigQuery billing.",
    )
    parser.add_argument(
        "--max-refinement-attempts",
        type=int,
        default=2,
        help="Number of self-refinement attempts after the initial execution (default: 2).",
    )

    return parser.parse_args()


def main() -> None:
    """Main entry point with command-line argument support."""
    args = parse_arguments()

    models_to_test = args.models if args.models else [args.model]

    if args.domain:
        domains_to_test = [args.domain]
    elif args.domains:
        domains_to_test = args.domains
    else:
        domains_to_test = [
            "Diagnostic_Procedures",
            "Disease_Diagnosis_and_Outcomes",
            "Laboratory_Results_Analysis",
            "Medication_Management",
            "Patient_Demographics_and_Admissions",
            "Vital_Signs_Monitoring",
        ]

    difficulties_to_test = (
        args.difficulties if args.difficulties else ["easy_level_queries", "medium_level_queries", "hard_level_queries"]
    )
    if getattr(args, "split", None):
        splits_to_test = [args.split]
    elif getattr(args, "splits", None):
        splits_to_test = args.splits
    else:
        splits_to_test = list(BENCHMARK_SPLITS)

    ray_init_kwargs: Optional[Dict[str, Any]] = None
    if args.ray_init_kwargs:
        try:
            parsed_ray_kwargs = json.loads(args.ray_init_kwargs)
            if not isinstance(parsed_ray_kwargs, dict):
                raise ValueError("ray init kwargs must decode to a JSON object")
            ray_init_kwargs = parsed_ray_kwargs
        except Exception as exc:
            raise SystemExit(f"Failed to parse --ray-init-kwargs: {exc}")

    tester_kwargs: Dict[str, Any] = {
        "model_id_override": args.model_id_override,
        "tokenizer_id": args.tokenizer,
        "revision": args.revision,
        "download_dir": args.download_dir,
        "tensor_parallel_size": args.tensor_parallel_size,
        "gpu_memory_utilization": args.gpu_memory_utilization,
        "dtype": args.dtype,
        "max_model_len": args.max_model_len,
        "temperature": args.temperature,
        "top_p": args.top_p,
        "top_k": args.top_k,
        "max_new_tokens": args.max_new_tokens,
        "stop_sequences": args.stop_sequences,
        "trust_remote_code": args.trust_remote_code,
        "data_root": args.data_root,
        "output_root": args.output_dir,
        "bigquery_project": args.bigquery_project,
        "max_refinement_attempts": args.max_refinement_attempts,
        "server_url": args.vllm_server_url,
        "server_api_key": args.vllm_server_api_key,
        "server_model": args.vllm_server_model,
        "enable_batch_inference": args.enable_batch_inference,
        "batch_size": args.batch_size,
        "batch_concurrency": args.batch_concurrency,
        "max_num_batched_tokens": args.max_num_batched_tokens,
        "ray_address": args.ray_address,
        "ray_namespace": args.ray_namespace,
        "ray_init_kwargs": ray_init_kwargs,
    }

    print("=" * 60)
    print("CLINICAL BENCHMARK TESTING CONFIGURATION (data/splits)")
    print("=" * 60)
    print(f"Models: {', '.join(models_to_test)}")
    print(f"Splits: {', '.join(splits_to_test)}")
    print(f"Domains: {', '.join(domains_to_test)}")
    print(f"Difficulties: {', '.join(difficulties_to_test)}")
    print(f"Max queries per level: {args.max_queries if args.max_queries else 'All'}")
    print(f"Batch inference: {'enabled' if args.enable_batch_inference else 'disabled'}")
    if args.vllm_server_url:
        print(f"OpenAI-compatible server: {args.vllm_server_url}")
    print("=" * 60)

    if len(models_to_test) == 1:
        model_id = models_to_test[0]
        print(f"Running single model experiment: {model_id}")
        results = run_single_model_experiment(
            model_name=model_id,
            domains=domains_to_test,
            difficulties=difficulties_to_test,
            max_queries_per_level=args.max_queries,
            splits=splits_to_test,
            tester_kwargs=tester_kwargs,
        )
    else:
        print(f"Running multi-model experiment: {', '.join(models_to_test)}")
        results = run_multi_model_experiment(
            model_names=models_to_test,
            domains=domains_to_test,
            difficulties=difficulties_to_test,
            max_queries_per_level=args.max_queries,
            splits=splits_to_test,
            tester_kwargs=tester_kwargs,
        )

    print("\n" + "=" * 60)
    print("EXPERIMENT COMPLETED SUCCESSFULLY")
    print("=" * 60)


if __name__ == "__main__":
    main()
