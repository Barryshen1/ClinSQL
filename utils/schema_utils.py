"""Helpers for loading auxiliary schema hints."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Iterable, List

from .constant import REPO_ROOT


DEFAULT_SCHEMA_CANDIDATES: List[Path] = [
    Path("/mnt/c/Clinical_Benchmark/model_inference/mimic4_schema.txt"),
    REPO_ROOT / "model_inference" / "mimic4_schema.txt",
    REPO_ROOT / "mimic4_schema.txt",
]


def load_mimic_schema_text(extra_search_paths: Iterable[Path] | None = None) -> str:
    candidates: List[Path] = []
    if extra_search_paths:
        candidates.extend(extra_search_paths)
    candidates.extend(DEFAULT_SCHEMA_CANDIDATES)

    for path in candidates:
        try:
            if path.exists():
                return path.read_text(encoding="utf-8")
        except Exception:
            continue

    logging.warning("MIMIC schema file not found; proceeding without schema context in prompts.")
    return ""
