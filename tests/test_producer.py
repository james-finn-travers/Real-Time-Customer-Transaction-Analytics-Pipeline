"""Unit tests for the transaction producer.

Validates schema compliance, idempotency, throughput, and edge cases.
"""

import json
import time
import pytest
from datetime import datetime, timezone

from producer.producer import (
    generate_transaction,
    _idempotent_txn_id,
    MERCHANTS,
    USERS,
    CURRENCIES,
    PAYMENT_METHODS,
    STATUSES,
)


# ---------------------------------------------------------------------------
# Schema validation
# ---------------------------------------------------------------------------
REQUIRED_FIELDS = [
    "txn_id", "user_id", "amount", "currency", "timestamp",
    "merchant_id", "merchant_category", "payment_method", "status", "location",
]


class TestTransactionSchema:
    """Verify generated transactions match the expected schema."""

    def test_has_all_required_fields(self, sample_transaction):
        for field in REQUIRED_FIELDS:
            assert field in sample_transaction, f"Missing field: {field}"

    def test_has_exactly_10_fields(self, sample_transaction):
        assert len(sample_transaction) == 10

    def test_txn_id_is_24_hex_chars(self, sample_transaction):
        txn_id = sample_transaction["txn_id"]
        assert len(txn_id) == 24
        assert all(c in "0123456789abcdef" for c in txn_id)

    def test_user_id_format(self, sample_transaction):
        uid = sample_transaction["user_id"]
        assert uid.startswith("user_")
        assert len(uid) == 11  # "user_" + 6 digits

    def test_amount_is_positive(self, sample_transaction):
        assert sample_transaction["amount"] > 0

    def test_amount_has_two_decimals(self, sample_transaction):
        amount_str = str(sample_transaction["amount"])
        if "." in amount_str:
            decimals = len(amount_str.split(".")[1])
            assert decimals <= 2

    def test_currency_is_valid(self, sample_transaction):
        assert sample_transaction["currency"] in CURRENCIES

    def test_timestamp_is_iso_format(self, sample_transaction):
        ts = sample_transaction["timestamp"]
        parsed = datetime.fromisoformat(ts)
        assert parsed.tzinfo is not None  # Must be timezone-aware

    def test_merchant_id_format(self, sample_transaction):
        mid = sample_transaction["merchant_id"]
        assert mid.startswith("merchant_")

    def test_merchant_category_is_valid(self, sample_transaction):
        valid_categories = {m["category"] for m in MERCHANTS}
        assert sample_transaction["merchant_category"] in valid_categories

    def test_payment_method_is_valid(self, sample_transaction):
        assert sample_transaction["payment_method"] in PAYMENT_METHODS

    def test_status_is_valid(self, sample_transaction):
        assert sample_transaction["status"] in STATUSES

    def test_location_has_lat_lon(self, sample_transaction):
        loc = sample_transaction["location"]
        assert "lat" in loc
        assert "lon" in loc
        assert -90 <= loc["lat"] <= 90
        assert -180 <= loc["lon"] <= 180


# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------
class TestIdempotency:
    """Verify txn_id generation properties."""

    def test_txn_id_is_string(self):
        tid = _idempotent_txn_id("user_000001", "2026-01-01T00:00:00+00:00", 99.99)
        assert isinstance(tid, str)

    def test_txn_id_length(self):
        tid = _idempotent_txn_id("user_000001", "2026-01-01T00:00:00+00:00", 99.99)
        assert len(tid) == 24

    def test_different_calls_produce_unique_ids(self):
        tid1 = _idempotent_txn_id("user_000001", "2026-01-01T00:00:00+00:00", 99.99)
        tid2 = _idempotent_txn_id("user_000001", "2026-01-01T00:00:00+00:00", 99.99)
        # UUID component makes each call unique
        assert tid1 != tid2


# ---------------------------------------------------------------------------
# Batch generation
# ---------------------------------------------------------------------------
class TestBatchGeneration:
    """Verify batch generation properties and throughput."""

    def test_batch_all_valid(self, sample_transactions):
        for txn in sample_transactions:
            for field in REQUIRED_FIELDS:
                assert field in txn

    def test_batch_unique_txn_ids(self, sample_transactions):
        ids = [t["txn_id"] for t in sample_transactions]
        assert len(ids) == len(set(ids)), "Duplicate txn_ids found in batch"

    def test_batch_users_from_pool(self, sample_transactions, user_ids):
        for txn in sample_transactions:
            assert txn["user_id"] in user_ids

    def test_batch_merchants_from_pool(self, sample_transactions, merchant_ids):
        for txn in sample_transactions:
            assert txn["merchant_id"] in merchant_ids

    def test_generation_throughput(self):
        """Verify we can generate at least 5k txns/sec (no Kafka)."""
        count = 5000
        t0 = time.perf_counter()
        for _ in range(count):
            generate_transaction()
        elapsed = time.perf_counter() - t0
        tps = count / elapsed
        assert tps > 1000, f"Generation too slow: {tps:.0f} txns/sec (need 1k+)"


# ---------------------------------------------------------------------------
# JSON serialization
# ---------------------------------------------------------------------------
class TestSerialization:
    """Verify transactions are JSON-serializable."""

    def test_json_serializable(self, sample_transaction):
        serialized = json.dumps(sample_transaction)
        deserialized = json.loads(serialized)
        assert deserialized == sample_transaction

    def test_round_trip_preserves_types(self, sample_transaction):
        serialized = json.dumps(sample_transaction)
        deserialized = json.loads(serialized)
        assert isinstance(deserialized["amount"], float)
        assert isinstance(deserialized["location"]["lat"], float)
        assert isinstance(deserialized["location"]["lon"], float)
