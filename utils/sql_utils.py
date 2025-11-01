"""Utilities for post-processing SQL emitted by models."""

from __future__ import annotations

import re


def clean_sql_response(response: str) -> str:
    if not response or not response.strip():
        return ""

    code_blocks = re.findall(r"```(?:sql)?\s*(.*?)\s*```", response, flags=re.DOTALL | re.IGNORECASE)
    if code_blocks:
        text = code_blocks[-1].strip()
    else:
        tag_match = re.search(r"\[sql\](.*?)(?:\[/sql\]|$)", response, flags=re.DOTALL | re.IGNORECASE)
        if tag_match:
            text = tag_match.group(1).strip()
        else:
            body = response.strip()
            lowered = body.lower()
            if "\nsql:" in lowered or lowered.startswith("sql:"):
                idx = lowered.rfind("sql:")
                if idx != -1:
                    body = body[idx:]
            m_with = re.search(r"(?is)(with\s+.*)$", body)
            m_sel = re.search(r"(?is)(select\s+.*)$", body)
            if m_with:
                text = m_with.group(1).strip()
            elif m_sel:
                text = m_sel.group(1).strip()
            else:
                text = body

    text = re.sub(r"```+", "", text)
    text = re.sub(r"\[/?sql\]", "", text, flags=re.IGNORECASE)

    m2_with = re.search(r"(?is)\bwith\b", text)
    m2_sel = re.search(r"(?is)\bselect\b", text)
    start_idx = m2_with.start() if m2_with else (m2_sel.start() if m2_sel else None)
    if start_idx is not None and start_idx > 0:
        text = text[start_idx:]

    if text and not text.rstrip().endswith(";"):
        text = text.rstrip() + ";"

    return text
