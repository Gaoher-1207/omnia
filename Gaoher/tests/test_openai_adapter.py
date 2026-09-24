import json
import sys
import threading
import types
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from Gaoher.ai.agent.model_adapter import (
    ModelCallOptions,
    ModelIntegrationPending,
    ModelOutputTooLarge,
    ModelRequestCancelled,
    ProviderFailure,
    ProviderTimeout,
    ProviderUnavailable,
    StructuredOutputFailure,
)
from Gaoher.ai.agent.openai_adapter import OpenAIModelAdapter


class FakeResponses:
    def __init__(self, output_text=None, error=None, on_call=None):
        self.output_text = output_text
        self.error = error
        self.on_call = on_call
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if self.on_call:
            self.on_call()
        if self.error:
            raise self.error
        return SimpleNamespace(output_text=self.output_text)


class FakeClient:
    def __init__(self, responses):
        self.responses = responses
        self.option_calls = []

    def with_options(self, **kwargs):
        self.option_calls.append(kwargs)
        return self


def adapter_for(output_text=None, *, error=None, on_call=None, max_output_tokens=777):
    responses = FakeResponses(output_text, error=error, on_call=on_call)
    client = FakeClient(responses)
    adapter = OpenAIModelAdapter(client=client, model="offline-test-model", max_output_tokens=max_output_tokens)
    return adapter, client, responses


class OpenAIAdapterTests(unittest.TestCase):
    def test_successful_structured_response_uses_responses_schema(self):
        expected = {"kind": "answer", "message": "Hello.", "action": None}
        adapter, client, responses = adapter_for(json.dumps(expected))
        result = adapter.generate_structured("respond", {"message": "hi"}, options=ModelCallOptions())
        self.assertEqual(result, expected)
        self.assertEqual(client.option_calls[0]["timeout"], 15.0)
        self.assertEqual(client.option_calls[0]["max_retries"], 0)
        request = responses.calls[0]
        self.assertEqual(request["model"], "offline-test-model")
        self.assertEqual(request["max_output_tokens"], 777)
        self.assertEqual(request["text"]["format"]["type"], "json_schema")
        self.assertTrue(request["text"]["format"]["strict"])
        self.assertFalse(request["text"]["format"]["schema"]["additionalProperties"])

    def test_successful_routing_response(self):
        expected = {"category": "omnia", "policy": "study"}
        adapter, _, responses = adapter_for(json.dumps(expected))
        result = adapter.generate_structured("route_request", {"message": "What should I study?"}, options=ModelCallOptions())
        self.assertEqual(result, expected)
        self.assertEqual(responses.calls[0]["text"]["format"]["name"], "omnia_route")

    def test_nullable_optional_action_argument_is_normalized(self):
        expected = {"kind": "action", "message": "Create it?", "action": {
            "name": "create_task", "arguments": {"title": "Study", "due_at": None}
        }}
        adapter, _, _ = adapter_for(json.dumps(expected))
        result = adapter.generate_structured("respond", {}, options=ModelCallOptions())
        self.assertEqual(result["action"]["arguments"], {"title": "Study"})

    def test_malformed_provider_output_is_typed(self):
        adapter, _, _ = adapter_for("not-json")
        with self.assertRaises(StructuredOutputFailure):
            adapter.generate_structured("route_request", {}, options=ModelCallOptions())

    def test_provider_error_is_sanitized_and_typed(self):
        class RateLimitError(Exception):
            pass

        adapter, _, _ = adapter_for(error=RateLimitError("secret provider details"))
        with self.assertRaises(ProviderUnavailable) as raised:
            adapter.generate_structured("route_request", {}, options=ModelCallOptions())
        self.assertNotIn("secret", str(raised.exception))

    def test_provider_timeout_is_typed(self):
        class APITimeoutError(Exception):
            pass

        adapter, _, _ = adapter_for(error=APITimeoutError("sensitive transport detail"))
        with self.assertRaises(ProviderTimeout) as raised:
            adapter.generate_structured("respond", {}, options=ModelCallOptions())
        self.assertNotIn("sensitive", str(raised.exception))

    def test_cancellation_before_and_during_request(self):
        cancellation = threading.Event()
        cancellation.set()
        adapter, _, responses = adapter_for(json.dumps({"category": "general", "policy": "general"}))
        with self.assertRaises(ModelRequestCancelled):
            adapter.generate_structured("route_request", {}, options=ModelCallOptions(cancellation=cancellation))
        self.assertEqual(responses.calls, [])

        cancellation.clear()
        adapter, _, _ = adapter_for(
            json.dumps({"category": "general", "policy": "general"}),
            on_call=cancellation.set,
        )
        with self.assertRaises(ModelRequestCancelled):
            adapter.generate_structured("route_request", {}, options=ModelCallOptions(cancellation=cancellation))

    def test_oversized_output_is_rejected_before_mapping(self):
        adapter, _, _ = adapter_for(json.dumps({"message": "x" * 9_000}))
        with self.assertRaises(ModelOutputTooLarge):
            adapter.generate_structured("respond", {}, options=ModelCallOptions())

    def test_missing_api_configuration_fails_without_importing_sdk_or_network(self):
        with self.assertRaises(ModelIntegrationPending):
            OpenAIModelAdapter(model="offline-test-model", environ={})

    def test_missing_model_configuration_fails_closed(self):
        with self.assertRaises(ModelIntegrationPending):
            OpenAIModelAdapter(environ={"OPENAI_API_KEY": "test-only-placeholder"})

    def test_backend_environment_configures_sdk_client_without_network(self):
        responses = FakeResponses(json.dumps({"category": "general", "policy": "general"}))
        fake_client = FakeClient(responses)
        captured = {}

        def fake_openai(**kwargs):
            captured.update(kwargs)
            return fake_client

        fake_sdk = types.ModuleType("openai")
        fake_sdk.OpenAI = fake_openai
        with patch.dict(sys.modules, {"openai": fake_sdk}):
            adapter = OpenAIModelAdapter(environ={
                "OPENAI_API_KEY": "offline-test-placeholder",
                "OMNIA_OPENAI_MODEL": "offline-test-model",
                "OMNIA_OPENAI_MAX_OUTPUT_TOKENS": "512",
            })
        result = adapter.generate_structured("route_request", {}, options=ModelCallOptions())
        self.assertEqual(result, {"category": "general", "policy": "general"})
        self.assertEqual(captured["api_key"], "offline-test-placeholder")
        self.assertEqual(captured["max_retries"], 0)
        self.assertEqual(responses.calls[0]["model"], "offline-test-model")
        self.assertEqual(responses.calls[0]["max_output_tokens"], 512)

    def test_unexpected_provider_exception_maps_to_safe_provider_failure(self):
        adapter, _, _ = adapter_for(error=ValueError("secret implementation detail"))
        with self.assertRaises(ProviderFailure) as raised:
            adapter.generate_structured("respond", {}, options=ModelCallOptions())
        self.assertNotIn("secret", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
