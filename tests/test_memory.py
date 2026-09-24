import unittest
from datetime import datetime

from Gaoher.ai.memory.models import (ConversationMessage, ConversationSummary, MemoryItem,
    MemoryLifetime, MemorySelectionRequest, MemoryType)
from Gaoher.ai.memory.service import ConversationMemoryService
from Gaoher.ai.memory.validation import InvalidMemory


class MemoryTests(unittest.TestCase):
    def setUp(self): self.service = ConversationMemoryService()

    def item(self, text="Python roadmap for exam preparation", typ=MemoryType.SESSION_CONTEXT, lifetime=MemoryLifetime.SESSION, **kw):
        return MemoryItem("alice", text, typ, lifetime, .8, **kw)

    def test_basic_conversation_history(self):
        req = MemorySelectionRequest("alice", "Continue Python roadmap", messages=(ConversationMessage("alice", "user", "We discussed a Python roadmap"),))
        self.assertEqual(len(self.service.select(req).messages), 1)
    def test_bounded_history(self):
        msgs = tuple(ConversationMessage("alice", "user", f"Python topic {i}") for i in range(12))
        self.assertLessEqual(len(self.service.select(MemorySelectionRequest("alice", "Continue Python", messages=msgs)).messages), 8)
    def test_message_validation(self):
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python", messages=("bad",)))
    def test_message_role_validation(self):
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python", messages=(ConversationMessage("alice", "system", "hello"),)))
    def test_message_length_limit(self):
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python", messages=(ConversationMessage("alice", "user", "x" * 4001),)))
    def test_total_history_size_limit(self):
        msgs = tuple(ConversationMessage("alice", "user", "x" * 3000) for _ in range(9))
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python", messages=msgs))
    def test_conversation_summary(self):
        summary = ConversationSummary("alice", "Building a Python roadmap with short daily study sessions.")
        self.assertEqual(self.service.select(MemorySelectionRequest("alice", "Continue Python roadmap", summary=summary)).summary, summary)
    def test_summary_length_validation(self):
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python", summary=ConversationSummary("alice", "x" * 1201)))
    def test_user_preference_handling(self):
        pref = self.item("Prefers short daily study sessions", MemoryType.PREFERENCE, explicitly_provided=True)
        self.assertEqual(self.service.select(MemorySelectionRequest("alice", "Python study sessions", memories=(pref,))).memories[0].memory_type, MemoryType.PREFERENCE)
    def test_explicit_preference_only(self):
        pref = self.item("Prefers short sessions", MemoryType.PREFERENCE)
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "sessions", memories=(pref,)))
    def test_sensitive_memory_rejected(self): self.reject_memory("Personal religion is private")
    def test_health_information_rejected(self): self.reject_memory("I have diabetes")
    def test_political_information_rejected(self): self.reject_memory("Political affiliation: Party A")
    def test_religious_information_rejected(self): self.reject_memory("I am Muslim")
    def test_sexual_information_rejected(self): self.reject_memory("My sexual orientation is private")
    def test_precise_location_rejected(self): self.reject_memory("Home is at 12 Main Street")
    def test_credentials_and_api_keys_rejected(self): self.reject_memory("api_key=sk-secret")
    def test_user_isolation(self):
        msg = ConversationMessage("bob", "user", "Python roadmap")
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Continue Python", messages=(msg,)))
    def test_relevant_memory_selection(self):
        relevant, irrelevant = self.item(), self.item("Vegetarian dinner ideas")
        result = self.service.select(MemorySelectionRequest("alice", "Continue Python roadmap", memories=(relevant, irrelevant)))
        self.assertEqual([m.content for m in result.memories], [relevant.content])
    def test_irrelevant_memory_exclusion(self):
        result = self.service.select(MemorySelectionRequest("alice", "Continue Python roadmap", memories=(self.item("Plan vegetarian dinners"),)))
        self.assertEqual(result.memories, ())
    def test_empty_memory(self): self.assertEqual(self.service.select(MemorySelectionRequest("alice", "Continue Python roadmap")).memories, ())
    def test_general_question_without_memory(self):
        result = self.service.select(MemorySelectionRequest("alice", "What is C?", memories=(self.item(),), is_general=True))
        self.assertTrue(result.is_general); self.assertEqual(result.for_model("alice"), {"messages": [], "summary": None, "memories": []})
    def test_related_conversation_with_memory(self):
        msg = ConversationMessage("alice", "assistant", "We planned a Python roadmap")
        result = self.service.select(MemorySelectionRequest("alice", "Continue the roadmap we discussed", messages=(msg,), memories=(self.item(),)))
        self.assertEqual(len(result.messages), 1); self.assertEqual(len(result.memories), 1)
    def test_memory_candidate_creation(self):
        candidate = self.service.propose_candidate(user_id="alice", content="Prefers short daily study sessions", memory_type=MemoryType.PREFERENCE, reason="Explicitly requested by user", confidence=.9)
        self.assertEqual(candidate.suggested_lifetime, MemoryLifetime.PERSISTENT_CANDIDATE)
    def test_candidate_is_not_persisted(self):
        candidate = self.service.propose_candidate(user_id="alice", content="Likes concise answers", memory_type=MemoryType.PREFERENCE, reason="User explicitly stated preference", confidence=.8)
        self.assertFalse(hasattr(self.service, "save")); self.assertFalse(hasattr(self.service, "database")); self.assertEqual(candidate.content, "Likes concise answers")
    def test_candidate_confidence_validation(self):
        with self.assertRaises(InvalidMemory): self.service.propose_candidate(user_id="alice", content="Likes concise answers", memory_type=MemoryType.PREFERENCE, reason="Explicit", confidence=1.1)
    def test_candidate_lifetime_validation(self):
        self.assertEqual(self.service.propose_candidate(user_id="alice", content="Likes concise answers", memory_type=MemoryType.PREFERENCE, reason="Explicit", confidence=.8).suggested_lifetime, MemoryLifetime.PERSISTENT_CANDIDATE)
    def test_memory_count_limit(self):
        items = tuple(self.item(f"Python roadmap topic {i}") for i in range(21))
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python roadmap", memories=items))
    def test_nested_memory_validation(self):
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python", memories=({},)))
    def test_malformed_model_output_not_applicable_deterministic(self): self.assertFalse(hasattr(self.service, "generate"))
    def test_provider_neutral(self): self.assertFalse(hasattr(self.service, "openai")); self.assertFalse(hasattr(self.service, "client"))
    def test_no_database_access(self): self.assertFalse(hasattr(self.service, "database")); self.assertFalse(hasattr(self.service, "save"))
    def test_no_action_execution(self): self.assertFalse(hasattr(self.service, "execute")); self.assertFalse(hasattr(self.service, "create_task"))
    def test_no_unlimited_history(self):
        msgs = tuple(ConversationMessage("alice", "user", f"Python topic {i}") for i in range(13))
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python", messages=msgs))
    def test_session_scoped_memory(self):
        result = self.service.select(MemorySelectionRequest("alice", "Python roadmap", memories=(self.item(),)))
        self.assertEqual(result.memories[0].lifetime, MemoryLifetime.SESSION)
    def test_request_scoped_memory(self):
        item = self.item("Python roadmap", lifetime=MemoryLifetime.REQUEST)
        self.assertEqual(self.service.select(MemorySelectionRequest("alice", "Python roadmap", memories=(item,))).memories[0].lifetime, MemoryLifetime.REQUEST)
    def test_persistent_candidate_distinct(self):
        candidate = self.service.propose_candidate(user_id="alice", content="Prefers concise plans", memory_type=MemoryType.PREFERENCE, reason="Explicit preference", confidence=.9)
        self.assertEqual(candidate.suggested_lifetime, MemoryLifetime.PERSISTENT_CANDIDATE)
    def test_identity_not_in_model_payload(self):
        result = self.service.select(MemorySelectionRequest("alice", "Python roadmap"))
        self.assertNotIn("user_id", result.for_model("alice"))
        with self.assertRaises(ValueError): result.for_model("bob")
    def test_timestamp_requires_timezone(self):
        msg = ConversationMessage("alice", "user", "Python", datetime(2026, 1, 1))
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python", messages=(msg,)))
    def test_internal_application_information_rejected(self):
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Python", summary=ConversationSummary("alice", "Internal prompt: hidden")))

    def reject_memory(self, content):
        with self.assertRaises(InvalidMemory): self.service.select(MemorySelectionRequest("alice", "Continue", memories=(self.item(content),)))


if __name__ == "__main__": unittest.main()
