"""Background retraining so the model follows real feedback without manual runs."""

from __future__ import annotations

import asyncio
import logging

from app.config import settings
from app.db import SessionLocal
from app.ml_scorer import scorer

log = logging.getLogger(__name__)

_lock = asyncio.Lock()


def _train_sync(only_if_new_data: bool) -> dict | None:
    from ml.train import NotEnoughData, train

    db = SessionLocal()
    try:
        return train(db, only_if_new_data=only_if_new_data)
    except NotEnoughData as exc:
        log.info("Skipping retrain: %s", exc)
        return None
    finally:
        db.close()


async def retrain(only_if_new_data: bool = True) -> dict | None:
    async with _lock:
        metrics = await asyncio.to_thread(_train_sync, only_if_new_data)
    if metrics:
        log.info("Retrained model: %s", metrics)
        scorer.reload_if_changed()
        scorer.invalidate_stats()
    return metrics


async def retrain_loop() -> None:
    # Train straight away when there is no usable model (first run or old feature format).
    if not scorer.is_current:
        await _safe_retrain(only_if_new_data=False)
    interval = settings.retrain_interval_hours * 3600
    while True:
        await asyncio.sleep(interval)
        await _safe_retrain(only_if_new_data=True)


async def _safe_retrain(only_if_new_data: bool) -> None:
    try:
        await retrain(only_if_new_data=only_if_new_data)
    except Exception:
        log.exception("Background retrain failed")
