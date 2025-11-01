"""Benchmark-level constants shared across CLINSQL."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

BENCHMARK_DOMAINS = [
    "Diagnostic_Procedures",
    "Disease_Diagnosis_and_Outcomes",
    "Laboratory_Results_Analysis",
    "Medication_Management",
    "Patient_Demographics_and_Admissions",
    "Vital_Signs_Monitoring",
]

BENCHMARK_DIFFICULTIES = [
    "easy_level_queries",
    "medium_level_queries",
    "hard_level_queries",
]

BENCHMARK_SPLITS = ["test", "validation"]
