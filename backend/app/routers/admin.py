import hmac

from fastapi import APIRouter, Header, HTTPException

from app.config import settings
from app.ml_scorer import scorer
from app.training import retrain

router = APIRouter(prefix="/v1/admin", tags=["admin"])


def _check(token: str | None) -> None:
    if not settings.admin_token:
        raise HTTPException(status_code=404, detail="Not found")
    if not token or not hmac.compare_digest(token, settings.admin_token):
        raise HTTPException(status_code=403, detail="Invalid admin token")


@router.get("/model")
def model_info(x_admin_token: str | None = Header(default=None)):
    _check(x_admin_token)
    scorer.reload_if_changed()
    return {"loaded": scorer.is_current, "metrics": scorer.metrics}


@router.post("/retrain")
async def force_retrain(x_admin_token: str | None = Header(default=None)):
    _check(x_admin_token)
    metrics = await retrain(only_if_new_data=False)
    return {"retrained": metrics is not None, "metrics": metrics}
