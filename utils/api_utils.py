"""Factory helpers for proprietary model clients."""

from __future__ import annotations

import os

from .model_specs import ProprietaryModelSpec


def create_proprietary_client(
    spec: ProprietaryModelSpec,
    *,
    azure_endpoint: str | None = None,
    azure_api_key: str | None = None,
    azure_api_version: str | None = None,
):
    provider = spec.provider

    if provider == "google_gemini":
        from google import genai  # lazy import

        api_key = os.environ.get("GOOGLE_CLOUD_API_KEY")
        if not api_key:
            raise ValueError("GOOGLE_CLOUD_API_KEY must be set to use Gemini models.")
        return genai.Client(api_key=api_key)

    if provider == "azure_openai":
        from openai import AzureOpenAI

        endpoint = azure_endpoint or os.environ.get("AZURE_OPENAI_ENDPOINT")
        api_key = azure_api_key or os.environ.get("AZURE_OPENAI_API_KEY")
        api_version = azure_api_version or spec.azure_api_version
        if not endpoint or not api_key:
            raise ValueError(
                "Azure models require AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_API_KEY."
            )
        return AzureOpenAI(
            api_version=api_version,
            azure_endpoint=endpoint,
            api_key=api_key,
        )

    if provider == "xai_grok":
        from openai import OpenAI

        api_key_env = spec.api_key_env or "XAI_API_KEY"
        api_key = os.environ.get(api_key_env)
        if not api_key:
            raise ValueError(f"{api_key_env} must be set to use Grok models.")
        return OpenAI(api_key=api_key, base_url=spec.base_url or "https://api.x.ai/v1")

    if provider == "mistral":
        from mistralai.client import MistralClient

        api_key_env = spec.api_key_env or "MISTRAL_API_KEY"
        api_key = os.environ.get(api_key_env)
        if not api_key:
            raise ValueError(f"{api_key_env} must be set to use Mistral models.")
        return MistralClient(api_key=api_key)

    raise ValueError(f"Unsupported provider '{provider}'")
