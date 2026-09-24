import threading
import time
import unittest

from Gaoher.ai.agent.model_adapter import (
    MAX_MODEL_OUTPUT_BYTES,
    ModelCallOptions,
    ModelOutputTooLarge,
    ModelPayloadTooLarge,
    ModelRequestCancelled,
    ProviderTimeout,
    StructuredOutputFailure,
    call_structured,
)


class StubAdapter:
    def __init__(self, result=None, delay=0):
        self.result = result if result is not None else {"ok": True}
        self.delay = delay

    def generate_structured(self, task, payload, *, options):
        if self.delay:
            time.sleep(self.delay)
        return self.result


class ModelAdapterBoundaryTests(unittest.TestCase):
    def test_payload_limit(self):
        with self.assertRaises(ModelPayloadTooLarge):
            call_structured(StubAdapter(), "route", {"message": "x" * 40_000})

    def test_output_limit(self):
        with self.assertRaises(ModelOutputTooLarge):
            call_structured(StubAdapter({"text": "x" * MAX_MODEL_OUTPUT_BYTES}), "respond", {})

    def test_structured_output_must_be_json_serializable(self):
        with self.assertRaises(StructuredOutputFailure):
            call_structured(StubAdapter({"bad": object()}), "respond", {})

    def test_elapsed_timeout_is_detected(self):
        with self.assertRaises(ProviderTimeout):
            call_structured(
                StubAdapter(delay=0.02), "respond", {},
                options=ModelCallOptions(timeout_seconds=0.001),
            )

    def test_cancellation_before_call(self):
        cancellation = threading.Event()
        cancellation.set()
        with self.assertRaises(ModelRequestCancelled):
            call_structured(StubAdapter(), "respond", {}, options=ModelCallOptions(cancellation=cancellation))


if __name__ == "__main__":
    unittest.main()
