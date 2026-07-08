"""User settings endpoints — capture/refine and generation defaults."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .. import models
from ..database import get_db
from ..services import settings as settings_service

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("/captures", response_model=models.CaptureSettingsResponse)
async def get_capture_settings_endpoint(db: Session = Depends(get_db)):
    return settings_service.get_capture_settings(db)


@router.put("/captures", response_model=models.CaptureSettingsResponse)
async def update_capture_settings_endpoint(
    patch: models.CaptureSettingsUpdate,
    db: Session = Depends(get_db),
):
    return settings_service.update_capture_settings(db, patch.model_dump(exclude_unset=True))


@router.get("/generation", response_model=models.GenerationSettingsResponse)
async def get_generation_settings_endpoint(db: Session = Depends(get_db)):
    return settings_service.get_generation_settings(db)


@router.put("/generation", response_model=models.GenerationSettingsResponse)
async def update_generation_settings_endpoint(
    patch: models.GenerationSettingsUpdate,
    db: Session = Depends(get_db),
):
    return settings_service.update_generation_settings(db, patch.model_dump(exclude_unset=True))


@router.get("/fish-audio", response_model=models.FishAudioSettingsResponse)
async def get_fish_audio_settings_endpoint(db: Session = Depends(get_db)):
    from ..services import fish_audio_settings as fish_audio_service

    return models.FishAudioSettingsResponse(**fish_audio_service.get_status(db))


@router.put("/fish-audio", response_model=models.FishAudioSettingsResponse)
async def update_fish_audio_settings_endpoint(
    patch: models.FishAudioSettingsUpdate,
    db: Session = Depends(get_db),
):
    from ..services import fish_audio_settings as fish_audio_service

    try:
        fish_audio_service.set_api_key(db, patch.api_key)
    except ValueError as e:
        from fastapi import HTTPException

        raise HTTPException(status_code=400, detail=str(e))
    return models.FishAudioSettingsResponse(**fish_audio_service.get_status(db))


@router.post("/fish-audio/verify", response_model=models.FishAudioVerifyResponse)
async def verify_fish_audio_settings_endpoint(
    request: models.FishAudioVerifyRequest | None = None,
    db: Session = Depends(get_db),
):
    from fastapi import HTTPException

    from ..services import fish_audio_settings as fish_audio_service

    try:
        api_key = request.api_key if request else None
        result = await fish_audio_service.verify_api_key(api_key)
        return models.FishAudioVerifyResponse(**result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/fish-audio", response_model=models.FishAudioSettingsResponse)
async def clear_fish_audio_settings_endpoint(db: Session = Depends(get_db)):
    from ..services import fish_audio_settings as fish_audio_service

    fish_audio_service.clear_api_key(db)
    return models.FishAudioSettingsResponse(**fish_audio_service.get_status(db))
