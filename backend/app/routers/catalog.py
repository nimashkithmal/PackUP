from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import ActivityRule, CatalogItem

router = APIRouter(prefix="/v1", tags=["catalog"])


@router.get("/activities", response_model=list[str])
def activities(db: Session = Depends(get_db)):
    rows = db.query(ActivityRule.activity).distinct().all()
    return sorted(r[0] for r in rows)


@router.get("/catalog")
def catalog(db: Session = Depends(get_db)):
    return [
        {"item_id": i.id, "slug": i.slug, "name": i.name, "category": i.category}
        for i in db.query(CatalogItem).order_by(CatalogItem.category, CatalogItem.name).all()
    ]
