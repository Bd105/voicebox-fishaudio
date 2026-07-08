"""Tests for Fish Audio settings service."""

import os
import tempfile
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from backend.database.models import Base, FishAudioSettings
from backend.services import fish_audio_settings


@pytest.fixture
def db_session():
    temp_dir = tempfile.mkdtemp()
    db_path = Path(temp_dir) / "test.db"
    engine = create_engine(f"sqlite:///{db_path}")
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    db = SessionLocal()
    yield db
    db.close()


def test_set_and_get_api_key(db_session):
    fish_audio_settings.set_api_key(db_session, "test_key_abc123")
    assert fish_audio_settings.get_api_key(db_session) == "test_key_abc123"


def test_get_status_masks_key(db_session):
    fish_audio_settings.set_api_key(db_session, "test_key_abc123")
    status = fish_audio_settings.get_status(db_session)
    assert status["configured"] is True
    assert status["key_prefix"] == "test_key_abc"
    assert "test_key_abc123" not in str(status)


def test_clear_api_key(db_session):
    fish_audio_settings.set_api_key(db_session, "test_key_abc123")
    fish_audio_settings.clear_api_key(db_session)
    assert fish_audio_settings.get_api_key(db_session) is None
    assert fish_audio_settings.get_status(db_session)["configured"] is False


def test_resolve_api_key_prefers_database(db_session, monkeypatch):
    monkeypatch.setenv("FISH_API_KEY", "env_key")
    fish_audio_settings.set_api_key(db_session, "db_key")
    assert fish_audio_settings.resolve_api_key(db_session) == "db_key"


def test_resolve_api_key_falls_back_to_env(db_session, monkeypatch):
    monkeypatch.setenv("FISH_API_KEY", "env_key")
    assert fish_audio_settings.resolve_api_key(db_session) == "env_key"


def test_is_configured_false_without_key(db_session, monkeypatch):
    monkeypatch.delenv("FISH_API_KEY", raising=False)
    assert fish_audio_settings.is_configured(db_session) is False
