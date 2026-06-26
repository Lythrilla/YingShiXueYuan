from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import auth, crud, excel, models, schemas
from ..database import get_db

router = APIRouter(prefix="/api/admin", tags=["admin"])


# ---------- Auth ----------
@router.post("/login", response_model=schemas.TokenOut)
def login(payload: schemas.LoginRequest):
    if not auth.authenticate(payload.username, payload.password):
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    return schemas.TokenOut(token=auth.create_token(payload.username), username=payload.username)


# ---------- Resources ----------
@router.get("/resources", response_model=list[schemas.ResourceOut])
def admin_list_resources(db: Session = Depends(get_db), _: str = Depends(auth.require_admin)):
    return db.scalars(
        select(models.Resource).order_by(models.Resource.sort_order, models.Resource.id)
    ).all()


@router.post("/resources", response_model=schemas.ResourceOut, status_code=201)
def create_resource(
    payload: schemas.ResourceCreate,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    resource = models.Resource(**payload.model_dump())
    db.add(resource)
    db.commit()
    db.refresh(resource)
    return resource


@router.put("/resources/{resource_id}", response_model=schemas.ResourceOut)
def update_resource(
    resource_id: int,
    payload: schemas.ResourceUpdate,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    resource = db.get(models.Resource, resource_id)
    if not resource:
        raise HTTPException(status_code=404, detail="资源不存在")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(resource, key, value)
    db.commit()
    db.refresh(resource)
    return resource


@router.delete("/resources/{resource_id}", status_code=204)
def delete_resource(
    resource_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    resource = db.get(models.Resource, resource_id)
    if not resource:
        raise HTTPException(status_code=404, detail="资源不存在")
    db.delete(resource)
    db.commit()


# ---------- Slots ----------
@router.get("/slots", response_model=list[schemas.SlotOut])
def admin_list_slots(db: Session = Depends(get_db), _: str = Depends(auth.require_admin)):
    return db.scalars(
        select(models.TimeSlot).order_by(models.TimeSlot.sort_order, models.TimeSlot.id)
    ).all()


@router.post("/slots", response_model=schemas.SlotOut, status_code=201)
def create_slot(
    payload: schemas.SlotCreate,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    slot = models.TimeSlot(**payload.model_dump())
    db.add(slot)
    db.commit()
    db.refresh(slot)
    return slot


@router.put("/slots/{slot_id}", response_model=schemas.SlotOut)
def update_slot(
    slot_id: int,
    payload: schemas.SlotUpdate,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    slot = db.get(models.TimeSlot, slot_id)
    if not slot:
        raise HTTPException(status_code=404, detail="时间段不存在")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(slot, key, value)
    db.commit()
    db.refresh(slot)
    return slot


@router.delete("/slots/{slot_id}", status_code=204)
def delete_slot(
    slot_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    slot = db.get(models.TimeSlot, slot_id)
    if not slot:
        raise HTTPException(status_code=404, detail="时间段不存在")
    db.delete(slot)
    db.commit()


# ---------- Bookings ----------
def _query_bookings(
    db: Session,
    status: str | None,
    resource_id: int | None,
    date: str | None,
    keyword: str | None,
):
    stmt = select(models.Booking).order_by(models.Booking.date.desc(), models.Booking.id.desc())
    if status:
        stmt = stmt.where(models.Booking.status == status)
    if resource_id:
        stmt = stmt.where(models.Booking.resource_id == resource_id)
    if date:
        stmt = stmt.where(models.Booking.date == date)
    if keyword:
        like = f"%{keyword}%"
        stmt = stmt.where(
            (models.Booking.applicant_name.like(like))
            | (models.Booking.phone.like(like))
            | (models.Booking.instructor.like(like))
        )
    return db.scalars(stmt).all()


@router.get("/bookings", response_model=list[schemas.BookingOut])
def admin_list_bookings(
    status: str | None = None,
    resource_id: int | None = None,
    date: str | None = None,
    keyword: str | None = None,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    return _query_bookings(db, status, resource_id, date, keyword)


@router.post("/bookings/{booking_id}/verify", response_model=schemas.BookingOut)
def verify(
    booking_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    booking = db.get(models.Booking, booking_id)
    if not booking:
        raise HTTPException(status_code=404, detail="预约不存在")
    if booking.status == "cancelled":
        raise HTTPException(status_code=400, detail="已取消的预约不可核销")
    if booking.status == "verified":
        raise HTTPException(status_code=400, detail="该预约已核销")
    return crud.verify_booking(db, booking)


@router.post("/bookings/{booking_id}/cancel", response_model=schemas.BookingOut)
def cancel(
    booking_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    booking = db.get(models.Booking, booking_id)
    if not booking:
        raise HTTPException(status_code=404, detail="预约不存在")
    booking.status = "cancelled"
    db.commit()
    db.refresh(booking)
    return booking


@router.get("/stats")
def stats(db: Session = Depends(get_db), _: str = Depends(auth.require_admin)):
    all_bookings = db.scalars(select(models.Booking)).all()
    today = datetime.utcnow().strftime("%Y-%m-%d")
    return {
        "total": len(all_bookings),
        "booked": sum(1 for b in all_bookings if b.status == "booked"),
        "verified": sum(1 for b in all_bookings if b.status == "verified"),
        "cancelled": sum(1 for b in all_bookings if b.status == "cancelled"),
        "today": sum(1 for b in all_bookings if b.date == today and b.status != "cancelled"),
    }


@router.get("/export")
def export_bookings(
    status: str | None = None,
    resource_id: int | None = None,
    date: str | None = None,
    keyword: str | None = None,
    db: Session = Depends(get_db),
    _: str = Depends(auth.require_admin),
):
    bookings = _query_bookings(db, status, resource_id, date, keyword)
    content = excel.bookings_to_xlsx(bookings)
    filename = f"bookings_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.xlsx"
    return StreamingResponse(
        iter([content]),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )
