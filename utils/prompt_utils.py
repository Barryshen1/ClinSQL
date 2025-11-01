"""Prompt templates shared by inference scripts."""

from __future__ import annotations


def build_generation_prompt(question: str, schema_text: str | None = None) -> str:
    schema_section = (
        f"\n\nMIMIC-IV Schema Reference (HOSP + ICU):\n{schema_text}\n"
        if schema_text
        else ""
    )
    return (
        "You are a clinical data analyst expert specializing in the MIMIC-IV database. "
        "Your goal is to produce a correct BigQuery SQL query for the question below.\n\n"
        "Constraints:\n"
        "- Target platform: Google BigQuery.\n"
        "- Use the correct datasets: `physionet-data.mimiciv_3_1_hosp`, `physionet-data.mimiciv_3_1_icu`.\n"
        f"{schema_section}\n"
        "Clinical question:\n"
        f"\"{question}\"\n\n"
        "Your output should be organized in the following two parts:\n"
        "Reasoning:\n"
        "- Think step by step about relevant tables, joins, filters, groupings, and edge cases.\n"
        "- Briefly justify important choices.\n"
        "SQL (wrap the final query in a fenced code block using ```sql and ```):\n\n"
        "Think step by step and then generate the complete SQL query."
    )


def build_refinement_prompt(
    question: str,
    previous_sql: str,
    error_message: str,
    schema_text: str | None = None,
) -> str:
    schema_section = (
        f"\n\nMIMIC-IV Schema Reference (HOSP + ICU):\n{schema_text}\n"
        if schema_text
        else ""
    )
    return (
        "You are a clinical data analyst expert for the MIMIC-IV dataset. "
        "The following SQL failed to run on Google BigQuery. Refine it to resolve the error and better answer the question.\n\n"
        "Constraints:\n"
        "- Use valid BigQuery SQL.\n"
        "- Use the correct datasets: `physionet-data.mimiciv_3_1_hosp`, `physionet-data.mimiciv_3_1_icu`.\n"
        "- Modify only what is necessary; prefer minimal, correct fixes.\n"
        f"{schema_section}\n"
        "Clinical question:\n"
        f"{question}\n\n"
        "Previous SQL attempt (for reference):\n"
        f"```sql\n{previous_sql}\n```\n\n"
        "BigQuery error message:\n"
        f"{error_message}\n\n"
        "Your output should be organized in the following two parts:\n"
        "Reasoning:\n"
        "- Step by step, explain the cause of the error and the fix.\n"
        "- Justify key changes briefly.\n"
        "SQL (wrap the final corrected query in a fenced code block using ```sql and ```):\n\n"
        "Think step by step and then generate the complete corrected SQL query."
    )
