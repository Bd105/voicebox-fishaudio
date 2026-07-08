"""
Fish Audio cloud TTS backend.

Uses the official fish-audio-sdk to call the Fish Audio API for text-to-speech
and instant voice cloning via reference audio. No local model weights are
downloaded — inference runs on Fish Audio's servers.
"""

from __future__ import annotations

import asyncio
import io
import logging
from pathlib import Path
from typing import List, Optional, Tuple

import numpy as np
import soundfile as sf

from . import TTSBackend
from .base import combine_voice_prompts as _combine_voice_prompts
from ..services import fish_audio_settings

logger = logging.getLogger(__name__)

FISH_AUDIO_SAMPLE_RATE = 44100
FISH_AUDIO_MODELS = ("s2.1-pro", "s2.1-pro-free", "s2-pro", "s1")
DEFAULT_MODEL_SIZE = "s2.1-pro"


class FishAudioBackend:
    """Fish Audio cloud TTS backend — API-key based voice cloning."""

    def __init__(self):
        self.client = None
        self.model_size: str = DEFAULT_MODEL_SIZE
        self._model_load_lock = asyncio.Lock()

    def is_loaded(self) -> bool:
        return self.client is not None

    def _get_model_path(self, model_size: str = DEFAULT_MODEL_SIZE) -> str:
        return f"fish-audio:{model_size}"

    def _is_model_cached(self, model_size: str = DEFAULT_MODEL_SIZE) -> bool:
        return fish_audio_settings.is_configured()

    async def load_model(self, model_size: str = DEFAULT_MODEL_SIZE) -> None:
        """Initialize the Fish Audio API client for the given model variant."""
        if model_size not in FISH_AUDIO_MODELS:
            model_size = DEFAULT_MODEL_SIZE

        if self.client is not None and self.model_size == model_size:
            return

        async with self._model_load_lock:
            if self.client is not None and self.model_size == model_size:
                return

            api_key = fish_audio_settings.resolve_api_key()
            if not api_key:
                raise RuntimeError(
                    "Fish Audio API key not configured. Add your key in Settings → Models "
                    "or set the FISH_API_KEY environment variable."
                )

            from fishaudio import AsyncFishAudio

            if self.client is not None:
                await self.client.close()

            self.client = AsyncFishAudio(api_key=api_key)
            self.model_size = model_size
            logger.info("Fish Audio client initialized (model=%s)", model_size)

    def unload_model(self) -> None:
        """Close the API client."""
        if self.client is not None:
            client = self.client
            self.client = None

            async def _close():
                await client.close()

            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    asyncio.create_task(_close())
                else:
                    loop.run_until_complete(_close())
            except Exception:
                logger.debug("Fish Audio client close skipped", exc_info=True)

        logger.info("Fish Audio client unloaded")

    async def create_voice_prompt(
        self,
        audio_path: str,
        reference_text: str,
        use_cache: bool = True,
    ) -> Tuple[dict, bool]:
        """
        Store reference audio path for instant cloning at generation time.

        Fish Audio processes reference audio per request via ReferenceAudio.
        """
        voice_prompt = {
            "ref_audio": str(audio_path),
            "ref_text": reference_text,
        }
        return voice_prompt, False

    async def combine_voice_prompts(
        self,
        audio_paths: List[str],
        reference_texts: List[str],
    ) -> Tuple[np.ndarray, str]:
        return await _combine_voice_prompts(audio_paths, reference_texts)

    async def generate(
        self,
        text: str,
        voice_prompt: dict,
        language: str = "en",
        seed: Optional[int] = None,
        instruct: Optional[str] = None,
    ) -> Tuple[np.ndarray, int]:
        """Generate speech via the Fish Audio cloud API."""
        if self.client is None:
            await self.load_model(self.model_size)

        ref_audio = voice_prompt.get("ref_audio")
        ref_text = voice_prompt.get("ref_text", "")
        if not ref_audio:
            raise ValueError("Fish Audio requires reference audio for voice cloning")

        generation_text = text
        if instruct and instruct.strip():
            generation_text = f"[{instruct.strip()}] {text}"

        from fishaudio.exceptions import AuthenticationError, FishAudioError, RateLimitError
        from fishaudio.types import ReferenceAudio, TTSConfig

        audio_path = Path(ref_audio)
        if not audio_path.exists():
            raise FileNotFoundError(f"Reference audio not found: {ref_audio}")

        with open(audio_path, "rb") as f:
            ref_bytes = f.read()

        references = [ReferenceAudio(audio=ref_bytes, text=ref_text or "Reference sample.")]
        config = TTSConfig(format="wav", sample_rate=FISH_AUDIO_SAMPLE_RATE)

        try:
            audio_bytes = await self.client.tts.convert(
                text=generation_text,
                references=references,
                config=config,
                model=self.model_size,
            )
        except AuthenticationError as e:
            raise RuntimeError(
                "Fish Audio authentication failed. Check your API key in Settings → Models."
            ) from e
        except RateLimitError as e:
            raise RuntimeError("Fish Audio rate limit exceeded. Try again later.") from e
        except FishAudioError as e:
            raise RuntimeError(f"Fish Audio API error: {e}") from e

        audio, sample_rate = sf.read(io.BytesIO(audio_bytes), dtype="float32")
        if audio.ndim > 1:
            audio = np.mean(audio, axis=1)

        return audio.astype(np.float32), int(sample_rate)
