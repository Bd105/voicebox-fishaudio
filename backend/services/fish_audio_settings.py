"""Fish Audio API key storage and resolution."""

from __future__ import annotations

import logging
import os
from datetime import datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..database import FishAudioSettings as DBFishAudioSettings

logger = logging.getLogger(__name__)

SINGLETON_ID = 1
API_KEYS_URL = "https://fish.audio/app/api-keys"


def _get_or_create_row(db: Session) -> DBFishAudioSettings:
    row = db.query(DBFishAudioSettings).filter(DBFishAudioSettings.id == SINGLETON_ID).first()
    if row is None:
        row = DBFishAudioSettings(id=SINGLETON_ID)
        db.add(row)
        try:
            db.commit()
            db.refresh(row)
        except IntegrityError:
            db.rollback()
            row = db.query(DBFishAudioSettings).filter(DBFishAudioSettings.id == SINGLETON_ID).one()
    return row


def get_api_key(db: Session) -> str | None:
    """Return the stored Fish Audio API key, if any."""
    row = _get_or_create_row(db)
    return row.api_key


def resolve_api_key(db: Session | None = None) -> str | None:
    """Resolve Fish Audio API key: DB-stored key first, then FISH_API_KEY env."""
    owns_session = db is None
    if owns_session:
        from ..database import SessionLocal

        db = SessionLocal()
    try:
        stored = get_api_key(db)
        if stored:
            return stored
    finally:
        if owns_session:
            db.close()

    env_key = os.environ.get("FISH_API_KEY", "").strip()
    return env_key or None


def is_configured(db: Session | None = None) -> bool:
    """Whether a Fish Audio API key is available."""
    return bool(resolve_api_key(db))


def set_api_key(db: Session, api_key: str) -> DBFishAudioSettings:
    """Persist a Fish Audio API key."""
    key = api_key.strip()
    if not key:
        raise ValueError("API key cannot be empty")

    row = _get_or_create_row(db)
    row.api_key = key
    row.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(row)
    return row


def clear_api_key(db: Session) -> None:
    """Remove the stored Fish Audio API key."""
    row = _get_or_create_row(db)
    row.api_key = None
    row.updated_at = datetime.utcnow()
    db.commit()


def get_status(db: Session) -> dict:
    """Local view of Fish Audio configuration — never returns the full key."""
    row = _get_or_create_row(db)
    configured = bool(row.api_key) or bool(os.environ.get("FISH_API_KEY", "").strip())
    key_prefix = row.api_key[:12] if row.api_key else None
    return {
        "configured": configured,
        "key_prefix": key_prefix,
        "source": "database" if row.api_key else ("environment" if os.environ.get("FISH_API_KEY") else None),
        "api_keys_url": API_KEYS_URL,
        "updated_at": row.updated_at,
    }


async def verify_api_key(api_key: str | None = None) -> dict:
    """Verify a Fish Audio API key by calling account.get_credits()."""
    from fishaudio import AsyncFishAudio
    from fishaudio.exceptions import AuthenticationError, FishAudioError

    key = (api_key or "").strip()
    if not key:
        from ..database import SessionLocal

        db = SessionLocal()
        try:
            key = resolve_api_key(db)
        finally:
            db.close()

    if not key:
        raise ValueError("No Fish Audio API key configured")

    client = AsyncFishAudio(api_key=key)
    try:
        credits = await client.account.get_credits()
        return {
            "valid": True,
            "credit": getattr(credits, "credit", None),
        }
    except AuthenticationError as e:
        raise ValueError("Invalid Fish Audio API key") from e
    except FishAudioError as e:
        raise ValueError(f"Fish Audio API error: {e}") from e
    finally:
        await client.close()
