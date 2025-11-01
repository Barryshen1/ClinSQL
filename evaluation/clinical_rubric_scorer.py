#!/usr/bin/env python3
"""Clinical rubric scorer for Clinical Benchmark outputs.

This utility evaluates inference outputs produced by the benchmark:
- inference outputs live under outputs/inference/<model>/<split>/<category>/<difficulty>/<id>
- evaluation summaries are written to outputs/evaluation/

The current implementation supports GPT-5-Chat via the Azure OpenAI
endpoint (credentials supplied through CLI flags or environment variables).
"""

from __future__ import annotations

import argparse
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple, Any

import pandas as pd

# Optional dependency (loaded lazily)
try:  # Azure OpenAI SDK
    from openai import AzureOpenAI as _AzureOpenAI
except Exception:  # pragma: no cover - optional dependency
    _AzureOpenAI = None

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INFERENCE_ROOT = REPO_ROOT / "outputs" / "inference"
DEFAULT_EVALUATION_ROOT = REPO_ROOT / "outputs" / "evaluation"

SUPPORTED_MODELS: Dict[str, Dict[str, str]] = {
    "gpt-5-chat": {"client": "azure", "model_name": "gpt-5-chat"},
}

DIFFICULTY_DIRS = [
    "easy_level_queries",
    "medium_level_queries",
    "hard_level_queries",
]

DIFFICULTY_LABELS = {
    "easy_level_queries": "easy",
    "medium_level_queries": "medium",
    "hard_level_queries": "hard",
}


@dataclass
class EvaluationResult:
    node_id: str
    requirements: str
    score: float
    explanation: str
    critical: bool = False
    weight: int = 1


@dataclass
class ClinicalEvaluation:
    sample_path: str
    sql_score: float
    results_score: float
    sql_evaluations: Dict[str, EvaluationResult]
    results_evaluations: Dict[str, EvaluationResult]


@dataclass
class EvaluationRecord:
    evaluation: ClinicalEvaluation
    category: str
    difficulty_dir: str
    split: Optional[str]

    @property
    def difficulty_label(self) -> str:
        return DIFFICULTY_LABELS.get(self.difficulty_dir, self.difficulty_dir)


class ClinicalRubricNode:
    """Simple wrapper around rubric JSON tree."""

    def __init__(self, data: Dict[str, Any]):
        self.id = data["id"]
        self.requirements = data["requirements"]
        self.weight = int(data.get("weight", 1))
        self.sequential = bool(data.get("sequential", False))
        self.critical = bool(data.get("critical", False))
        self.scoring = data.get("scoring", "1/0")
        self.sub_tasks = [ClinicalRubricNode(child) for child in data.get("sub_tasks", [])]

    def is_leaf(self) -> bool:
        return not self.sub_tasks


class ClinicalRubricScorer:
    """Evaluates rubric trees using GPT-5-Chat through Azure OpenAI."""

    def __init__(
        self,
        model: str = "gpt-5-chat",
        azure_endpoint: Optional[str] = None,
        azure_api_key: Optional[str] = None,
        azure_api_version: str = "2024-12-01-preview",
    ):
        if model not in SUPPORTED_MODELS:
            raise ValueError(f"Unsupported judge model '{model}'. Supported: {list(SUPPORTED_MODELS.keys())}")
        self.model = model
        self.model_cfg = SUPPORTED_MODELS[model]

        self.azure_endpoint = azure_endpoint or os.environ.get("AZURE_OPENAI_ENDPOINT")
        self.azure_api_key = azure_api_key or os.environ.get("AZURE_OPENAI_API_KEY")
        self.azure_api_version = azure_api_version or os.environ.get("AZURE_OPENAI_API_VERSION", "2024-12-01-preview")

        if not self.azure_endpoint or not self.azure_api_key:
            raise ValueError("Set AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_API_KEY (or pass CLI flags) to run GPT-5-Chat evaluation.")
        if _AzureOpenAI is None:
            raise RuntimeError("Install openai>=1.40.0 to use Azure OpenAI judges (pip install openai).")

        self._last_azure_call_ts: float = 0.0
        self._next_azure_allowed_time: float = 0.0

    # ------------------------------------------------------------------
    # Public scoring entrypoint
    # ------------------------------------------------------------------
    def score_sample(self, sample_dir: Path) -> ClinicalEvaluation:
        sql_rubric_path = sample_dir / "sql_rubric_tree.json"
        results_rubric_path = sample_dir / "results_rubric_tree.json"
        if not sql_rubric_path.exists() or not results_rubric_path.exists():
            raise FileNotFoundError(f"Missing rubric files inside {sample_dir}")

        with open(sql_rubric_path, "r", encoding="utf-8") as fh:
            sql_rubric = ClinicalRubricNode(json.load(fh))
        with open(results_rubric_path, "r", encoding="utf-8") as fh:
            results_rubric = ClinicalRubricNode(json.load(fh))

        sample_files = self._load_sample_files(sample_dir)

        sql_evals: Dict[str, EvaluationResult] = {}
        results_evals: Dict[str, EvaluationResult] = {}

        if "test_sql" in sample_files:
            sql_evals = self._evaluate_tree(sql_rubric, sample_files, evaluation_type="sql")
        if "test_results" in sample_files:
            results_evals = self._evaluate_tree(results_rubric, sample_files, evaluation_type="results")

        sql_score = self._calculate_score(sql_rubric, sql_evals) if sql_evals else 0.0
        results_score = self._calculate_score(results_rubric, results_evals) if results_evals else 0.0

        return ClinicalEvaluation(
            sample_path=str(sample_dir),
            sql_score=sql_score,
            results_score=results_score,
            sql_evaluations=sql_evals,
            results_evaluations=results_evals,
        )

    # ------------------------------------------------------------------
    # Rubric traversal helpers
    # ------------------------------------------------------------------
    def _load_sample_files(self, sample_dir: Path) -> Dict[str, Any]:
        files: Dict[str, Any] = {}

        query_files = list(sample_dir.glob("query_*.txt"))
        if query_files:
            files["query"] = query_files[0].read_text(encoding="utf-8").strip()

        sql_files = list(sample_dir.glob("sql_*.sql"))
        if sql_files:
            files["test_sql"] = sql_files[0].read_text(encoding="utf-8").strip()

        result_files = list(sample_dir.glob("result_*.csv"))
        if result_files:
            files["test_results"] = pd.read_csv(result_files[0]).to_dict(orient="records")

        gold_sql = sample_dir / "gold_sql.sql"
        if gold_sql.exists():
            files["gold_sql"] = gold_sql.read_text(encoding="utf-8").strip()

        gold_results = sample_dir / "gold_results.csv"
        if gold_results.exists():
            files["gold_results"] = pd.read_csv(gold_results).to_dict(orient="records")

        return files

    def _evaluate_tree(self, node: ClinicalRubricNode, sample_files: Dict[str, Any], evaluation_type: str) -> Dict[str, EvaluationResult]:
        results: Dict[str, EvaluationResult] = {}
        self._evaluate_node(node, sample_files, evaluation_type, results)
        return results

    def _evaluate_node(
        self,
        node: ClinicalRubricNode,
        sample_files: Dict[str, Any],
        evaluation_type: str,
        evaluations: Dict[str, EvaluationResult],
    ) -> EvaluationResult:
        if node.is_leaf():
            leaf_eval = self._evaluate_leaf(node, sample_files, evaluation_type)
            evaluations[node.id] = leaf_eval
            return leaf_eval

        child_results = []
        for child in node.sub_tasks:
            child_results.append(self._evaluate_node(child, sample_files, evaluation_type, evaluations))
        # Aggregate child results to create a pseudo-node result for reporting
        score = self._calculate_node_score(node, evaluations)
        explanation = "; ".join(f"{child.node_id}:{child.score}" for child in child_results)
        result = EvaluationResult(
            node_id=node.id,
            requirements=node.requirements,
            score=score,
            explanation=f"Aggregated from children -> {explanation}",
            critical=node.critical,
            weight=node.weight,
        )
        evaluations[node.id] = result
        return result

    def _evaluate_leaf(self, node: ClinicalRubricNode, sample_files: Dict[str, Any], evaluation_type: str) -> EvaluationResult:
        prompt = self._build_prompt(node, sample_files, evaluation_type)
        score, explanation = self._call_judge(prompt)
        return EvaluationResult(
            node_id=node.id,
            requirements=node.requirements,
            score=score,
            explanation=explanation,
            critical=node.critical,
            weight=node.weight,
        )

    def _calculate_score(self, node: ClinicalRubricNode, evaluations: Dict[str, EvaluationResult]) -> float:
        return self._calculate_node_score(node, evaluations)

    def _calculate_node_score(self, node: ClinicalRubricNode, evaluations: Dict[str, EvaluationResult]) -> float:
        if node.is_leaf():
            return evaluations.get(node.id, EvaluationResult(node.id, node.requirements, 0.0, "")).score

        if node.sequential:
            return self._calculate_sequential_score(node, evaluations)
        return self._calculate_critical_first_score(node, evaluations)

    def _calculate_critical_first_score(self, node: ClinicalRubricNode, evaluations: Dict[str, EvaluationResult]) -> float:
        critical_children = [child for child in node.sub_tasks if child.critical]
        non_critical_children = [child for child in node.sub_tasks if not child.critical]

        for child in critical_children:
            if self._calculate_node_score(child, evaluations) < 1.0:
                return 0.0

        if not non_critical_children:
            return 1.0

        total_weight = sum(child.weight for child in non_critical_children)
        if total_weight == 0:
            return 1.0
        weighted_sum = 0.0
        for child in non_critical_children:
            weighted_sum += child.weight * self._calculate_node_score(child, evaluations)
        return weighted_sum / total_weight

    def _calculate_sequential_score(self, node: ClinicalRubricNode, evaluations: Dict[str, EvaluationResult]) -> float:
        total_weight = 0.0
        weighted_sum = 0.0
        for child in node.sub_tasks:
            score = self._calculate_node_score(child, evaluations)
            weighted_sum += child.weight * score
            total_weight += child.weight
            if score < 1.0:
                break
        if total_weight == 0:
            return 0.0
        return weighted_sum / total_weight

    # ------------------------------------------------------------------
    # Prompting helpers
    # ------------------------------------------------------------------
    def _build_prompt(self, node: ClinicalRubricNode, sample_files: Dict[str, Any], evaluation_type: str) -> str:
        query = sample_files.get("query", "")
        test_sql = sample_files.get("test_sql", "")
        gold_sql = sample_files.get("gold_sql", "")
        test_results = sample_files.get("test_results")
        gold_results = sample_files.get("gold_results")

        parts = [
            "You are an expert clinical data QA judge assessing SQL-based answers.",
            "Follow the rubric requirements precisely. Respond with JSON on two lines:",
            "Score: <0 or 1>",
            "Explanation: <brief reason>",
            "---",
            f"Rubric node requirements:\n{node.requirements}",
            f"Evaluation target: {evaluation_type}",
        ]

        if query:
            parts.append(f"Clinical question: {query}")
        if test_sql:
            parts.append(f"Model SQL:\n```sql\n{test_sql}\n```")
        if gold_sql:
            parts.append(f"Reference SQL:\n```sql\n{gold_sql}\n```")
        if test_results is not None:
            parts.append(f"Model results rows (JSON):\n{json.dumps(test_results, indent=2)}")
        if gold_results is not None:
            parts.append(f"Reference results rows (JSON):\n{json.dumps(gold_results, indent=2)}")

        parts.append("Output strictly as: Score: <0 or 1>\nExplanation: <text>")
        return "\n\n".join(parts)

    def _call_judge(self, prompt: str) -> Tuple[float, str]:
        response = self._call_azure(prompt)
        try:
            score_line, explanation_line = response.strip().split("\n", 1)
            score = float(score_line.split(":", 1)[1].strip().split()[0])
            explanation = explanation_line.split(":", 1)[1].strip()
        except Exception:
            score = 1.0 if "1" in response else 0.0
            explanation = response.strip()
        return score, explanation

    def _call_azure(self, prompt: str) -> str:
        now = time.time()
        if now < self._next_azure_allowed_time:
            time.sleep(self._next_azure_allowed_time - now)
        client = _AzureOpenAI(
            api_version=self.azure_api_version,
            azure_endpoint=self.azure_endpoint,
            api_key=self.azure_api_key,
        )
        attempt_params = ["max_completion_tokens", "max_tokens"]
        for param_name in attempt_params:
            try:
                response = client.chat.completions.create(
                    model=self.model_cfg["model_name"],
                    messages=[{"role": "user", "content": prompt}],
                    temperature=0.2,
                    **{param_name: 1024},
                )
                text = response.choices[0].message.content
                break
            except Exception as exc:
                text = f"Error: {exc}"
        self._last_azure_call_ts = time.time()
        self._next_azure_allowed_time = self._last_azure_call_ts + 0.8
        return text


# ----------------------------------------------------------------------
# Helper utilities for iterating experiment outputs
# ----------------------------------------------------------------------

def resolve_inference_root(path: Optional[str]) -> Path:
    return _resolve_path(path, DEFAULT_INFERENCE_ROOT)


def resolve_evaluation_root(path: Optional[str]) -> Path:
    root = _resolve_path(path, DEFAULT_EVALUATION_ROOT)
    root.mkdir(parents=True, exist_ok=True)
    return root


def _resolve_path(path_str: Optional[str], default: Path) -> Path:
    if path_str:
        candidate = Path(path_str).expanduser()
        if not candidate.is_absolute():
            candidate = REPO_ROOT / candidate
        return candidate.resolve()
    return default.resolve()


def available_models(inference_root: Path) -> List[str]:
    if not inference_root.exists():
        return []
    return sorted([p.name for p in inference_root.iterdir() if p.is_dir()])


def available_splits(model_root: Path) -> List[str]:
    splits = [p.name for p in model_root.iterdir() if p.is_dir()]
    out = []
    for split in ["test", "validation"]:
        if split in splits:
            out.append(split)
    if not out:
        out.append(None)
    return out


def available_categories(split_root: Path) -> List[str]:
    return sorted([p.name for p in split_root.iterdir() if p.is_dir()])


def iter_samples(
    inference_root: Path,
    model: str,
    split: Optional[str] = None,
    category: Optional[str] = None,
    difficulty: Optional[str] = None,
) -> Iterable[Path]:
    model_root = inference_root / model
    if not model_root.exists():
        return []
    split_roots = [model_root / split] if split else [model_root]
    for split_root in split_roots:
        if not split_root.exists():
            continue
        categories = [category] if category else available_categories(split_root)
        for cat in categories:
            cat_dir = split_root / cat
            if not cat_dir.exists():
                continue
            difficulties = [difficulty] if difficulty else DIFFICULTY_DIRS
            for diff in difficulties:
                diff_dir = cat_dir / diff
                if not diff_dir.exists():
                    continue
                for sample_dir in sorted(p for p in diff_dir.iterdir() if p.is_dir()):
                    if (sample_dir / "sql_rubric_tree.json").exists():
                        yield sample_dir


# ----------------------------------------------------------------------
# Aggregation helpers
# ----------------------------------------------------------------------

def summarise_evaluations(evaluations: List[ClinicalEvaluation]) -> Dict[str, Any]:
    if not evaluations:
        return {
            "total_samples": 0,
            "average_sql_score": None,
            "average_results_score": None,
        }
    avg_sql = sum(e.sql_score for e in evaluations) / len(evaluations)
    avg_results = sum(e.results_score for e in evaluations) / len(evaluations)
    return {
        "total_samples": len(evaluations),
        "average_sql_score": round(avg_sql, 6),
        "average_results_score": round(avg_results, 6),
    }


def _round_score(value: Optional[float]) -> Optional[float]:
    if value is None:
        return None
    return round(value, 6)


def _serialise_node_results(results: Dict[str, EvaluationResult]) -> Dict[str, Any]:
    return {
        node_id: {
            "score": res.score,
            "explanation": res.explanation,
            "critical": res.critical,
            "weight": res.weight,
        }
        for node_id, res in results.items()
    }


def _evaluation_to_summary(evaluation: ClinicalEvaluation) -> Dict[str, Any]:
    return {
        "sample_path": evaluation.sample_path,
        "sql_score": evaluation.sql_score,
        "results_score": evaluation.results_score,
    }


def _evaluation_to_detailed(evaluation: ClinicalEvaluation) -> Dict[str, Any]:
    payload = _evaluation_to_summary(evaluation)
    payload["sql_evaluations"] = _serialise_node_results(evaluation.sql_evaluations)
    payload["results_evaluations"] = _serialise_node_results(evaluation.results_evaluations)
    return payload


def _stats_from_records(records: List[EvaluationRecord]) -> Dict[str, Any]:
    if not records:
        return {
            "total_samples": 0,
            "average_sql_score": None,
            "average_results_score": None,
        }
    total = len(records)
    avg_sql = sum(rec.evaluation.sql_score for rec in records) / total
    avg_results = sum(rec.evaluation.results_score for rec in records) / total
    return {
        "total_samples": total,
        "average_sql_score": _round_score(avg_sql),
        "average_results_score": _round_score(avg_results),
    }


def _difficulty_breakdown(records: List[EvaluationRecord]) -> Dict[str, Any]:
    breakdown: Dict[str, Any] = {}
    for difficulty_dir in DIFFICULTY_DIRS:
        diff_records = [rec for rec in records if rec.difficulty_dir == difficulty_dir]
        if diff_records:
            label = DIFFICULTY_LABELS.get(difficulty_dir, difficulty_dir)
            breakdown[label] = _stats_from_records(diff_records)
    # Include any non-standard difficulty directories that may appear.
    for rec in records:
        if rec.difficulty_dir not in DIFFICULTY_LABELS:
            label = rec.difficulty_dir
            if label not in breakdown:
                extra_records = [r for r in records if r.difficulty_dir == rec.difficulty_dir]
                breakdown[label] = _stats_from_records(extra_records)
    return breakdown


def _build_scenario_breakdown(records: List[EvaluationRecord]) -> List[Dict[str, Any]]:
    scenarios: List[Dict[str, Any]] = []
    categories: Dict[str, List[EvaluationRecord]] = {}
    for rec in records:
        categories.setdefault(rec.category, []).append(rec)
    for category in sorted(categories):
        category_records = categories[category]
        scenario_summary = {"category": category}
        scenario_summary.update(_stats_from_records(category_records))
        scenario_summary["difficulty_breakdown"] = _difficulty_breakdown(category_records)
        scenarios.append(scenario_summary)
    return scenarios


def _build_split_summary(model: str, split: Optional[str], records: List[EvaluationRecord]) -> Dict[str, Any]:
    summary = {
        "experiment_model": model,
        "split": split or "none",
        "category": "all_categories",
        "difficulty": "all",
    }
    summary.update(_stats_from_records(records))
    summary["difficulty_breakdown"] = _difficulty_breakdown(records)
    return summary


def _category_summary(
    model: str,
    category: str,
    split: Optional[str],
    records: List[EvaluationRecord],
    selected_difficulty: Optional[str] = None,
) -> Dict[str, Any]:
    difficulty_label = selected_difficulty or "all"
    summary = {
        "experiment_model": model,
        "category": category,
        "split": split or "none",
        "difficulty": difficulty_label,
    }
    summary.update(_stats_from_records(records))
    summary["difficulty_breakdown"] = _difficulty_breakdown(records)
    return summary


def write_aggregate(output_dir: Path, filename: str, data: Dict[str, Any]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    with open(output_dir / filename, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)


def score_test_samples(
    test_dir: Path,
    model: str = "gpt-5-chat",
    scorer_kwargs: Optional[Dict[str, Any]] = None,
) -> List[ClinicalEvaluation]:
    scorer = ClinicalRubricScorer(
        model=model,
        **(scorer_kwargs or {}),
    )
    evaluations = []
    for difficulty_dir in DIFFICULTY_DIRS:
        level_path = test_dir / difficulty_dir
        if not level_path.exists():
            continue
        for sample_dir in sorted(p for p in level_path.iterdir() if p.is_dir()):
            if (sample_dir / "sql_rubric_tree.json").exists():
                evaluations.append(scorer.score_sample(sample_dir))
    return evaluations


# ----------------------------------------------------------------------
# CLI command implementations
# ----------------------------------------------------------------------

def _difficulty_to_dir(difficulty: Optional[str]) -> Optional[str]:
    if difficulty is None:
        return None
    mapping = {
        "easy": "easy_level_queries",
        "medium": "medium_level_queries",
        "hard": "hard_level_queries",
    }
    if difficulty not in mapping:
        raise ValueError("Difficulty must be one of: easy, medium, hard")
    return mapping[difficulty]


def _prepare_scorer_kwargs(args: argparse.Namespace) -> Dict[str, Any]:
    return {
        k: v
        for k, v in {
            "azure_endpoint": args.azure_endpoint,
            "azure_api_key": args.azure_api_key,
            "azure_api_version": args.azure_api_version,
        }.items()
        if v is not None
    }


def cmd_list(args: argparse.Namespace) -> None:
    inference_root = resolve_inference_root(args.inference_root)
    models = available_models(inference_root)
    if not models:
        print("No inference outputs found.")
        return
    print("Available models:")
    for model in models:
        model_root = inference_root / model
        splits = available_splits(model_root)
        splits_str = ", ".join([s or "(no split)" for s in splits])
        print(f"- {model}: splits [{splits_str}]")


def cmd_single(args: argparse.Namespace) -> None:
    sample_dir = Path(args.sample_dir).expanduser().resolve()
    if not sample_dir.exists():
        raise FileNotFoundError(f"Sample directory not found: {sample_dir}")

    scorer = ClinicalRubricScorer(
        model=args.judge_model,
        **_prepare_scorer_kwargs(args),
    )
    evaluation = scorer.score_sample(sample_dir)
    print("=== Single Sample Evaluation ===")
    print(f"Sample: {sample_dir}")
    print(f"SQL score: {evaluation.sql_score:.3f}")
    print(f"Results score: {evaluation.results_score:.3f}")

    evaluation_root = resolve_evaluation_root(args.evaluation_root)
    output_dir = evaluation_root / "single_sample" / sample_dir.name
    write_aggregate(output_dir, "detailed_grading.json", _evaluation_to_detailed(evaluation))
    print(f"Detailed grading saved to {output_dir / 'detailed_grading.json'}")


def cmd_category(args: argparse.Namespace) -> None:
    inference_root = resolve_inference_root(args.inference_root)
    evaluation_root = resolve_evaluation_root(args.evaluation_root)
    difficulty_dir = _difficulty_to_dir(args.difficulty)

    samples = list(
        iter_samples(
            inference_root,
            args.model,
            split=args.split,
            category=args.category,
            difficulty=difficulty_dir,
        )
    )
    if not samples:
        print("No samples found for the specified filters.")
        return

    scorer = ClinicalRubricScorer(model=args.judge_model, **_prepare_scorer_kwargs(args))
    evaluations = [scorer.score_sample(sample) for sample in samples]
    records = [
        EvaluationRecord(
            evaluation=ev,
            category=args.category,
            difficulty_dir=sample.parent.name,
            split=args.split,
        )
        for sample, ev in zip(samples, evaluations)
    ]

    summary = _category_summary(args.model, args.category, args.split, records, args.difficulty)
    print("=== Category Summary ===")
    print(f"Total samples: {summary['total_samples']}")
    print(f"Average SQL score: {summary['average_sql_score']}")
    print(f"Average Results score: {summary['average_results_score']}")

    output_dir = evaluation_root / args.model
    if args.split:
        output_dir = output_dir / args.split
    output_dir = output_dir / args.category
    if difficulty_dir:
        output_dir = output_dir / difficulty_dir

    sorted_records = sorted(records, key=lambda rec: rec.evaluation.sample_path)
    write_aggregate(
        output_dir,
        "scoring_results.json",
        {
            "summary": summary,
            "samples": [_evaluation_to_summary(rec.evaluation) for rec in sorted_records],
        },
    )
    write_aggregate(
        output_dir,
        "detailed_grading.json",
        {
            "summary": summary,
            "detailed_evaluations": [_evaluation_to_detailed(rec.evaluation) for rec in sorted_records],
        },
    )
    print(f"Results written to {output_dir}")


def cmd_full(args: argparse.Namespace) -> None:
    inference_root = resolve_inference_root(args.inference_root)
    evaluation_root = resolve_evaluation_root(args.evaluation_root)
    model_root = inference_root / args.model
    if not model_root.exists():
        raise FileNotFoundError(f"Model outputs not found: {model_root}")

    splits = args.splits or [s for s in ["test", "validation"] if (model_root / s).exists()]
    if not splits:
        splits = [None]

    scorer = ClinicalRubricScorer(model=args.judge_model, **_prepare_scorer_kwargs(args))

    for split in splits:
        split_label = split or "nosplit"
        print(f"=== Running split: {split_label} ===")
        split_records: List[EvaluationRecord] = []

        split_root = model_root / split if split else model_root
        categories = available_categories(split_root)

        for category in categories:
            category_samples = list(
                iter_samples(
                    inference_root,
                    args.model,
                    split=split,
                    category=category,
                    difficulty=None,
                )
            )
            if not category_samples:
                continue
            category_evaluations = [scorer.score_sample(sample) for sample in category_samples]
            category_records = [
                EvaluationRecord(
                    evaluation=ev,
                    category=category,
                    difficulty_dir=sample.parent.name,
                    split=split,
                )
                for sample, ev in zip(category_samples, category_evaluations)
            ]
            split_records.extend(category_records)

            category_summary = _category_summary(args.model, category, split, category_records)
            print(
                f"[{split_label}] {category}: "
                f"avg SQL={category_summary['average_sql_score']} "
                f"avg results={category_summary['average_results_score']}"
            )

        if not split_records:
            print(f"No evaluated samples found for split {split_label}.")
            continue

        sorted_records = sorted(split_records, key=lambda rec: rec.evaluation.sample_path)
        split_output = evaluation_root / args.model
        if split:
            split_output = split_output / split

        split_summary = _build_split_summary(args.model, split, split_records)
        write_aggregate(
            split_output,
            "scoring_results.json",
            {
                "summary": split_summary,
                "samples": [_evaluation_to_summary(rec.evaluation) for rec in sorted_records],
            },
        )
        write_aggregate(
            split_output,
            "detailed_grading.json",
            {
                "summary": split_summary,
                "detailed_evaluations": [_evaluation_to_detailed(rec.evaluation) for rec in sorted_records],
            },
        )
        write_aggregate(
            split_output,
            "difficulty_scoring_results.json",
            {
                "experiment_model": args.model,
                "split": split or "none",
                "difficulty_breakdown": _difficulty_breakdown(split_records),
            },
        )
        write_aggregate(
            split_output,
            "scenario_scoring_results.json",
            {
                "experiment_model": args.model,
                "split": split or "none",
                "scenarios": _build_scenario_breakdown(split_records),
            },
        )
        print(f"Split summary stored in {split_output / 'scoring_results.json'}")


def cmd_test(args: argparse.Namespace) -> None:
    test_dir = Path(args.test_dir).expanduser().resolve()
    evaluations = score_test_samples(
        test_dir,
        model=args.judge_model,
        scorer_kwargs=_prepare_scorer_kwargs(args),
    )
    summary = summarise_evaluations(evaluations)
    print(summary)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Clinical rubric scorer")
    parser.add_argument("--inference-root", help="Path to inference outputs root", default=None)
    parser.add_argument("--evaluation-root", help="Path to evaluation output root", default=None)
    parser.add_argument("--judge-model", default="gpt-5-chat", choices=list(SUPPORTED_MODELS.keys()))
    parser.add_argument("--azure-endpoint", help="Azure OpenAI endpoint")
    parser.add_argument("--azure-api-key", help="Azure OpenAI API key")
    parser.add_argument("--azure-api-version", help="Azure OpenAI API version", default="2024-12-01-preview")
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List available models and splits")
    list_parser.set_defaults(func=cmd_list)

    single_parser = subparsers.add_parser("single", help="Score a single sample directory")
    single_parser.add_argument("sample_dir", help="Path to sample directory")
    single_parser.set_defaults(func=cmd_single)

    category_parser = subparsers.add_parser("category", help="Score a category/difficulty subset")
    category_parser.add_argument("model", help="Model name under outputs/inference")
    category_parser.add_argument("category", help="Clinical category name")
    category_parser.add_argument("--difficulty", choices=["easy", "medium", "hard"], help="Difficulty level")
    category_parser.add_argument("--split", choices=["test", "validation"], help="Dataset split")
    category_parser.set_defaults(func=cmd_category)

    full_parser = subparsers.add_parser("full", help="Score all categories and difficulties for a model")
    full_parser.add_argument("model", help="Model name under outputs/inference")
    full_parser.add_argument("--splits", nargs="+", choices=["test", "validation"], help="Splits to evaluate")
    full_parser.set_defaults(func=cmd_full)

    test_parser = subparsers.add_parser("test", help="Score samples under a local test directory")
    test_parser.add_argument("test_dir", help="Directory containing rubric-structured samples")
    test_parser.set_defaults(func=cmd_test)

    return parser


def main_cli() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main_cli()
