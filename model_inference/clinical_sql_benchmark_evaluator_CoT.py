"""
Clinical SQL Benchmark Evaluator (API CoT)

 Evaluate proprietary LLM text-to-SQL capabilities on clinical data (MIMIC-IV)
 using chain-of-thought prompting with optional self-refinement. Integrates with
 official APIs (Azure OpenAI and Google Gemini) and writes artifacts to
 outputs/inference/. For open-source models via vLLM, use
 clinical_sql_benchmark_evaluator_vllm.py.

 Supported proprietary models (Section 5.1, ClinSQL paper):
 GPT-5, GPT-5-mini, GPT-5-nano, GPT-4.1, o4-mini, Gemini-2.5-Pro,
 Gemini-2.5-Flash, Grok-4-Fast-Reasoning, Grok-4-Fast-Non-Reasoning,
 Mistral-Medium.

 Required credentials:
 - Azure OpenAI: AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY (and optionally AZURE_OPENAI_API_VERSION)
 - Google Gemini: GOOGLE_CLOUD_API_KEY
 - xAI Grok: XAI_API_KEY
 - Mistral: MISTRAL_API_KEY
"""

import os
import json
import time
import pandas as pd
import logging
import shutil
import argparse
from typing import Dict, List, Tuple, Optional, Any
from pathlib import Path
from google.cloud import bigquery
from google.genai import types

from utils import (
    BENCHMARK_DIFFICULTIES,
    BENCHMARK_DOMAINS,
    BENCHMARK_SPLITS,
    ProprietaryModelSpec,
    PROPRIETARY_MODEL_SPECS,
    SUPPORTED_PROPRIETARY_MODELS,
    create_proprietary_client,
    build_generation_prompt,
    build_refinement_prompt,
    clean_sql_response,
    load_mimic_schema_text,
)
class SQLGenerator:
    """Generate and refine SQL using the appropriate proprietary provider."""

    def __init__(self, client, spec: ProprietaryModelSpec, model_alias: str):
        self.client = client
        self.spec = spec
        self.model_alias = model_alias
        self.provider = spec.provider
        self.model_name = spec.api_model
        self.azure_deployment = spec.azure_deployment or spec.api_model
        self.use_responses_api = spec.use_responses_api
        # Load schema text once for reuse in prompts
        self.schema_text = load_mimic_schema_text()
    
    def generate_sql(self, question: str) -> str:
        """Generate SQL query using the configured proprietary model (CoT format)."""
        prompt = build_generation_prompt(question, self.schema_text)

        try:
            return self._dispatch_generation(prompt)
        except Exception as e:
            logging.error(f"Error generating SQL with {self.model_alias}: {e}")
            return ""

    def refine_sql(self, question: str, previous_sql: str, error_message: str) -> str:
        """Ask the model to refine a failing SQL query."""
        prompt = build_refinement_prompt(
            question=question,
            previous_sql=previous_sql,
            error_message=error_message,
            schema_text=self.schema_text,
        )

        try:
            return self._dispatch_generation(prompt)
        except Exception as e:
            logging.error(f"Error refining SQL with {self.model_alias}: {e}")
            return ""

    # ---- Provider-specific helpers -------------------------------------------------

    def _dispatch_generation(self, prompt: str) -> str:
        if self.provider == "google_gemini":
            return self._generate_sql_gemini(prompt)
        if self.provider == "azure_openai":
            if self.use_responses_api:
                return self._generate_sql_openai_responses(prompt)
            return self._generate_sql_openai_chat(prompt)
        if self.provider == "xai_grok":
            return self._generate_sql_openai_chat(prompt)
        if self.provider == "mistral":
            return self._generate_sql_mistral(prompt)
        raise ValueError(f"Unsupported provider: {self.provider}")

    def _generate_sql_openai_chat(self, prompt: str) -> str:
        """Generate SQL using OpenAI-compatible Chat Completions."""
        preferred_temp = getattr(self.spec, "default_temperature", 0.1)
        model_id = self.azure_deployment if self.provider == "azure_openai" else self.model_name

        def _invoke(temp: float):
            return self.client.chat.completions.create(
                model=model_id,
                messages=[{"role": "user", "content": prompt}],
                temperature=temp,
            )

        try:
            response = _invoke(preferred_temp)
        except Exception as exc:
            msg = str(exc).lower()
            if preferred_temp != 1.0 and "temperature" in msg and "unsupported" in msg:
                logging.warning(
                    "Temperature %.2f not supported for %s; retrying with default 1.0",
                    preferred_temp,
                    self.model_name,
                )
                response = _invoke(1.0)
            else:
                raise

        if not response or not getattr(response, "choices", None):
            logging.error("Chat Completions returned an empty response")
            return ""

        first_choice = response.choices[0]
        message = getattr(first_choice, "message", None)
        content = getattr(message, "content", None) if message else None
        if not content:
            logging.error("Chat Completions returned empty content")
            return ""

        return clean_sql_response(str(content).strip())

    def _generate_sql_openai_responses(self, prompt: str) -> str:
        """Generate SQL using Azure OpenAI Responses API (o-series etc.)."""
        try:
            resp = self.client.responses.create(
                model=self.azure_deployment,
                input=[
                    {"role": "user", "content": [{"type": "input_text", "text": prompt}]}
                ],
                max_output_tokens=2048,
            )

            if hasattr(resp, "output_text") and resp.output_text:
                return clean_sql_response(resp.output_text)

            text = None
            if hasattr(resp, "output") and resp.output:
                first = resp.output[0]
                content_list = getattr(first, "content", None)
                if content_list:
                    part0 = content_list[0]
                    text = getattr(part0, "text", None)

            if not text:
                logging.error("Responses API returned no text content")
                return ""

            return clean_sql_response(text.strip())
        except Exception as e:
            logging.error(f"Responses API generation failed: {e}")
            return ""
    
    def _generate_sql_gemini(self, prompt: str) -> str:
        """Generate SQL using Google Gemini"""
        contents = [
            types.Content(
                role="user",
                parts=[types.Part(text=prompt)]
            )
        ]

        if "pro" in self.model_name.lower():
            temperature = 1
            top_p = 0.95
        else:  # flash model
            temperature = 1
            top_p = 1
            
        generate_content_config = types.GenerateContentConfig(
            temperature=temperature,
            top_p=top_p,
            seed=0,
            max_output_tokens=65535,
            safety_settings=[
                types.SafetySetting(category="HARM_CATEGORY_HATE_SPEECH", threshold="OFF"),
                types.SafetySetting(category="HARM_CATEGORY_DANGEROUS_CONTENT", threshold="OFF"),
                types.SafetySetting(category="HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold="OFF"),
                types.SafetySetting(category="HARM_CATEGORY_HARASSMENT", threshold="OFF")
            ],
            thinking_config=types.ThinkingConfig(
                thinking_budget=-1,
            ),
        )

        backoffs = [2, 4, 8]
        last_err = None
        for attempt, delay in enumerate([0] + backoffs):
            if delay:
                time.sleep(delay)
            try:
                chunks = self.client.models.generate_content_stream(
                    model=self.model_name,
                    contents=contents,
                    config=generate_content_config,
                )
                buf = []
                for ch in chunks:
                    if hasattr(ch, "text") and ch.text:
                        buf.append(ch.text)
                text = ("".join(buf)).strip()
                if not text:
                    logging.error("Gemini returned empty text response")
                    return ""
                return clean_sql_response(text)
            except Exception as e:
                msg = str(e)
                last_err = msg
                if "429" in msg or "RESOURCE_EXHAUSTED" in msg or "rate" in msg.lower():
                    logging.warning(f"Gemini rate limited (attempt {attempt+1}); retrying after {delay}s")
                    continue
                logging.error(f"Error generating SQL (non-retryable): {msg}")
                return ""
        logging.error(f"Error generating SQL after retries: {last_err}")
        return ""

    def _generate_sql_mistral(self, prompt: str) -> str:
        """Generate SQL using the official Mistral chat client."""
        messages = [{"role": "user", "content": prompt}]
        temperature = 0.1
        max_tokens = 2048

        chat_attr = getattr(self.client, "chat", None)
        if callable(chat_attr):
            # Newer mistralai clients expose chat(...) directly
            response = chat_attr(
                model=self.model_name,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
            )
        else:
            response = self.client.chat.complete(
                model=self.model_name,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
            )

        if not response or not getattr(response, "choices", None):
            logging.error("Mistral chat completion returned no choices")
            return ""

        choice0 = response.choices[0]
        message = getattr(choice0, "message", None)
        content = None
        if isinstance(message, dict):
            content = message.get("content")
        else:
            content = getattr(message, "content", None)
        if not content:
            logging.error("Mistral chat completion returned empty content")
            return ""

        # content for Mistral SDK is a list of blocks with type/text
        if isinstance(content, list) and content:
            text_parts = []
            for block in content:
                text = getattr(block, "text", None)
                if text:
                    text_parts.append(text)
            content = "\n".join(text_parts)

        if hasattr(content, "text"):
            content = content.text

        if not isinstance(content, str):
            logging.error("Unexpected Mistral content format")
            return ""

        return clean_sql_response(content.strip())


class SQLExecutor:
    """Execute SQL queries using BigQuery with optional self-refinement support"""

    def __init__(self, client, model_name: str = "GPT-5-mini", project_id: Optional[str] = None):
        self.client = client
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
        model_name: str = "GPT-5-mini",
        data_root: Optional[Path] = None,
        output_root: Optional[Path] = None,
        bigquery_project: Optional[str] = None,
        azure_endpoint: Optional[str] = None,
        azure_api_key: Optional[str] = None,
        azure_api_version: Optional[str] = None,
        max_refinement_attempts: int = 2,
    ):
        self.model_name = model_name  # Alias used for outputs
        if model_name not in PROPRIETARY_MODEL_SPECS:
            raise ValueError(
                f"Model '{model_name}' is not supported. "
                f"Choose from: {', '.join(SUPPORTED_PROPRIETARY_MODELS)}"
            )
        self.model_spec = PROPRIETARY_MODEL_SPECS[model_name]
        provider = self.model_spec.provider
        logging.info(
            "Initializing proprietary model '%s' via provider '%s' (api model: %s)",
            model_name,
            provider,
            self.model_spec.api_model,
        )

        azure_version_override = (
            azure_api_version
            or os.environ.get("AZURE_OPENAI_API_VERSION")
            or self.model_spec.azure_api_version
        )

        self.client = create_proprietary_client(
            self.model_spec,
            azure_endpoint=azure_endpoint,
            azure_api_key=azure_api_key,
            azure_api_version=azure_version_override,
        )
        
        project_id = bigquery_project or os.environ.get("BIGQUERY_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")
        self.sql_generator = SQLGenerator(self.client, self.model_spec, model_name)
        self.sql_executor = SQLExecutor(self.client, model_name, project_id=project_id)
        self.max_refinement_attempts = max_refinement_attempts
        
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
    
    def process_single_query(self, query_file: Path, domain: str, difficulty: str) -> Dict:
        """Process a single benchmark query with self-refinement attempts."""
        try:
            # Read query
            with open(query_file, 'r', encoding='utf-8') as f:
                question = f.read().strip()

            self.logger.info(f"Processing: {query_file.parent.name} - {question[:80]}...")

            attempts: List[Dict] = []

            # Initial SQL generation
            sql = self.sql_generator.generate_sql(question)
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
            "model": self.model_name
        }
        
        # Track attempt-wise success counts (per-round execution)
        num_attempts = 1 + self.max_refinement_attempts
        attempt_success_counts = {i: 0 for i in range(1, num_attempts + 1)}
        
        for i, query_file in enumerate(query_files, 1):
            self.logger.info(f"Query {i}/{len(query_files)}")
            
            result = self.process_single_query(query_file, domain, difficulty)
            
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
        
        self.logger.info(f"Starting Clinical Benchmark Testing for model: {self.model_name}")
        
        num_attempts = 1 + self.max_refinement_attempts

        overall_summary = {
            "model": self.model_name,
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
        self.logger.info(f"BENCHMARK TESTING COMPLETE - {self.model_name}")
        self.logger.info(f"Total Queries (all splits): {total_queries}")
        self.logger.info(f"Total Successful (all splits): {total_successful}")
        self.logger.info(f"Overall Success Rate: {overall_rate:.1f}%")
        self.logger.info(f"Results saved to: {self.output_path / self.model_name}")
        self.logger.info("=" * 60)
        
        return overall_summary


def test_multiple_models(model_names: List[str],
                        domains: Optional[List[str]] = None,
                        difficulties: Optional[List[str]] = None,
                        max_queries_per_level: Optional[int] = None,
                        tester_kwargs: Optional[Dict[str, Any]] = None):
    """Test multiple models on the clinical benchmark"""
    all_results = {}
    tester_kwargs = tester_kwargs or {}
    
    for model_name in model_names:
        print(f"\n{'='*60}")
        print(f"TESTING MODEL: {model_name}")
        print(f"{'='*60}")
        
        tester = ClinicalBenchmarkTester(model_name=model_name, **tester_kwargs)
        model_results = tester.run_benchmark_test(
            domains=domains,
            difficulties=difficulties, 
            max_queries_per_level=max_queries_per_level
        )
        all_results[model_name] = model_results
    
    return all_results


def run_single_model_experiment(model_name: str, 
                               domains: Optional[List[str]] = None,
                               difficulties: Optional[List[str]] = None,
                               max_queries_per_level: Optional[int] = None,
                               tester_kwargs: Optional[Dict[str, Any]] = None):
    """Run benchmark test for a single model with flexible configuration"""
    tester = ClinicalBenchmarkTester(model_name=model_name, **(tester_kwargs or {}))
    return tester.run_benchmark_test(
        domains=domains,
        difficulties=difficulties,
        max_queries_per_level=max_queries_per_level
    )

def run_multi_model_experiment(model_names: List[str],
                             domains: Optional[List[str]] = None,
                             difficulties: Optional[List[str]] = None,
                             max_queries_per_level: Optional[int] = None,
                             tester_kwargs: Optional[Dict[str, Any]] = None):
    """Run benchmark test for multiple models with flexible configuration"""
    return test_multiple_models(
        model_names=model_names,
        domains=domains,
        difficulties=difficulties,
        max_queries_per_level=max_queries_per_level,
        tester_kwargs=tester_kwargs
    )

def run_domain_comparison_experiment(domain: str,
                                   model_names: List[str],
                                   max_queries_per_level: Optional[int] = None,
                                   tester_kwargs: Optional[Dict[str, Any]] = None):
    """Compare multiple models on a specific domain"""
    results = {}
    tester_kwargs = tester_kwargs or {}
    for model_name in model_names:
        print(f"\nTesting {model_name} on {domain}...")
        tester = ClinicalBenchmarkTester(model_name=model_name, **tester_kwargs)
        results[model_name] = tester.run_benchmark_test(
            domains=[domain],
            max_queries_per_level=max_queries_per_level
        )
    return results

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description="Clinical SQL Benchmark Evaluator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Test Gemini-2.5-Flash on all Diagnostic_Procedures difficulty levels
  python clinical_sql_benchmark_evaluator_CoT.py --model Gemini-2.5-Flash --domain Diagnostic_Procedures
  
  # Test specific difficulty levels
  python clinical_sql_benchmark_evaluator_CoT.py --model Gemini-2.5-Flash --domain Diagnostic_Procedures --difficulties easy_level_queries medium_level_queries
  
  # Test multiple models
  python clinical_sql_benchmark_evaluator_CoT.py --models Gemini-2.5-Flash Gemini-2.5-Pro --domain Diagnostic_Procedures
  
  # Limit number of queries per level
  python clinical_sql_benchmark_evaluator_CoT.py --model GPT-5-nano --domain Diagnostic_Procedures --max-queries 5
  
  # Test multiple domains
  python clinical_sql_benchmark_evaluator_CoT.py --model Gemini-2.5-Flash --domains Diagnostic_Procedures Laboratory_Results_Analysis
        """
    )
    
    # Available options
    AVAILABLE_MODELS = SUPPORTED_PROPRIETARY_MODELS
    AVAILABLE_DOMAINS = [
        "Diagnostic_Procedures", "Disease_Diagnosis_and_Outcomes", "Laboratory_Results_Analysis",
        "Medication_Management", "Patient_Demographics_and_Admissions", "Vital_Signs_Monitoring"
    ]
    AVAILABLE_DIFFICULTIES = ["easy_level_queries", "medium_level_queries", "hard_level_queries"]
    
    # Model selection (single or multiple)
    model_group = parser.add_mutually_exclusive_group(required=True)
    supported_str = ", ".join(AVAILABLE_MODELS)
    model_group.add_argument(
        "--model",
        choices=AVAILABLE_MODELS,
        help=f"Single proprietary model to test. Supported: {supported_str}",
    )
    model_group.add_argument(
        "--models",
        nargs="+",
        choices=AVAILABLE_MODELS,
        help=f"Multiple proprietary models to test (choose from: {supported_str})",
    )
    
    # Domain selection (single or multiple)
    domain_group = parser.add_mutually_exclusive_group()
    domain_group.add_argument("--domain", choices=AVAILABLE_DOMAINS,
                            help="Single domain to test")
    domain_group.add_argument("--domains", nargs="+", choices=AVAILABLE_DOMAINS,
                            help="Multiple domains to test (default: all domains)")
    
    # Difficulty selection
    parser.add_argument("--difficulties", nargs="+", choices=AVAILABLE_DIFFICULTIES,
                       help="Difficulty levels to test (default: all levels)")
    
    # Query limit
    parser.add_argument("--max-queries", type=int,
                       help="Maximum number of queries per difficulty level (default: all queries)")
    
    return parser.parse_args()

def main():
    """Main function with command-line argument support"""
    args = parse_arguments()
    
    # Determine models to test
    if args.model:
        models_to_test = [args.model]
    else:
        models_to_test = args.models
    
    # Determine domains to test
    if args.domain:
        domains_to_test = [args.domain]
    elif args.domains:
        domains_to_test = args.domains
    else:
        # Default to all domains if none specified
        domains_to_test = [
            "Diagnostic_Procedures", "Disease_Diagnosis_and_Outcomes", "Laboratory_Results_Analysis",
            "Medication_Management", "Patient_Demographics_and_Admissions", "Vital_Signs_Monitoring"
        ]
    
    # Determine difficulties to test (default: all)
    difficulties_to_test = args.difficulties if args.difficulties else ["easy_level_queries", "medium_level_queries", "hard_level_queries"]
    
    # Print experiment configuration
    print("=" * 60)
    print("CLINICAL BENCHMARK TESTING CONFIGURATION (data/splits)")
    print("=" * 60)
    print(f"Models: {', '.join(models_to_test)}")
    print(f"Domains: {', '.join(domains_to_test)}")
    print(f"Difficulties: {', '.join(difficulties_to_test)}")
    print(f"Max queries per level: {args.max_queries if args.max_queries else 'All'}")
    print("=" * 60)
    
    # Run experiments
    if len(models_to_test) == 1:
        # Single model experiment
        print(f"Running single model experiment: {models_to_test[0]}")
        results = run_single_model_experiment(
            model_name=models_to_test[0],
            domains=domains_to_test,
            difficulties=difficulties_to_test,
            max_queries_per_level=args.max_queries
        )
    else:
        # Multi-model experiment
        print(f"Running multi-model experiment: {', '.join(models_to_test)}")
        results = run_multi_model_experiment(
            model_names=models_to_test,
            domains=domains_to_test,
            difficulties=difficulties_to_test,
            max_queries_per_level=args.max_queries
        )
    
    print("\n" + "=" * 60)
    print("EXPERIMENT COMPLETED SUCCESSFULLY")
    print("=" * 60)


if __name__ == "__main__":
    main() 
