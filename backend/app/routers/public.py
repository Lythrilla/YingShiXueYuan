from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import crud, models, schemas
from ..database import get_db

router = APIRouter(prefix="/api", tags=["public"])


@router.get("/resources", response_model=list[schemas.ResourceOut])
def list_resources(db: Session = Depends(get_db)):
    return db.scalars(
        select(models.Resource)
        .where(models.Resource.is_active == True)  # noqa: E712
        .order_by(models.Resource.sort_order, models.Resource.id)
    ).all()


@router.get("/slots", response_model=list[schemas.SlotOut])
def list_slots(db: Session = Depends(get_db)):
    return db.scalars(
        select(models.TimeSlot)
        .where(models.TimeSlot.is_active == True)  # noqa: E712
        .order_by(models.TimeSlot.sort_order, models.TimeSlot.id)
    ).all()


@router.get("/availability/{resource_id}", response_model=schemas.ResourceAvailability)
def availability(resource_id: int, date: str, db: Session = Depends(get_db)):
    resource = db.get(models.Resource, resource_id)
    if not resource or not resource.is_active:
        raise HTTPException(status_code=404, detail="资源不存在")
    slots = db.scalars(
        select(models.TimeSlot)
        .where(models.TimeSlot.is_active == True)  # noqa: E712
        .order_by(models.TimeSlot.sort_order, models.TimeSlot.id)
    ).all()
    out = []
    for slot in slots:
        used = crud.booked_quantity(db, resource_id, slot.id, date)
        out.append(
            schemas.SlotAvailability(
                slot=slot,
                total_quantity=resource.total_quantity,
                booked_quantity=used,
                available=max(resource.total_quantity - used, 0),
            )
        )
    return schemas.ResourceAvailability(resource=resource, date=date, slots=out)


@router.post("/bookings", response_model=schemas.BookingOut, status_code=201)
def create_booking(payload: schemas.BookingCreate, db: Session = Depends(get_db)):
    resource = db.get(models.Resource, payload.resource_id)
    if not resource or not resource.is_active:
        raise HTTPException(status_code=404, detail="资源不存在")
    if not resource.individual_bookable:
        raise HTTPException(
            status_code=400, detail="该资源学生个人不可预约，请联系指导老师统一安排。"
        )
    slot = db.get(models.TimeSlot, payload.slot_id)
    if not slot or not slot.is_active:
        raise HTTPException(status_code=404, detail="时间段不存在")
    if payload.quantity < 1:
        raise HTTPException(status_code=400, detail="预约数量至少为 1")

    used = crud.booked_quantity(db, resource.id, slot.id, payload.date)
    if used + payload.quantity > resource.total_quantity:
        remaining = max(resource.total_quantity - used, 0)
        raise HTTPException(
            status_code=409,
            detail=f"该时段名额不足，仅剩 {remaining} 个可预约。",
        )

    booking = models.Booking(
        resource_id=resource.id,
        slot_id=slot.id,
        date=payload.date,
        applicant_name=payload.applicant_name,
        phone=payload.phone,
        major=payload.major,
        num_people=payload.num_people,
        instructor=payload.instructor,
        description=payload.description,
        quantity=payload.quantity,
        status="booked",
    )
    db.add(booking)
    db.commit()
    db.refresh(booking)
    return booking
