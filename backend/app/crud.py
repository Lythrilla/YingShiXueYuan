from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from . import models


def booked_quantity(db: Session, resource_id: int, slot_id: int, date: str) -> int:
    """某资源在指定日期/时段已被占用的数量（不含已取消）。"""
    total = db.scalar(
        select(func.coalesce(func.sum(models.Booking.quantity), 0)).where(
            models.Booking.resource_id == resource_id,
            models.Booking.slot_id == slot_id,
            models.Booking.date == date,
            models.Booking.status != "cancelled",
        )
    )
    return int(total or 0)


def verify_booking(db: Session, booking: models.Booking) -> models.Booking:
    booking.status = "verified"
    booking.verified_at = datetime.utcnow()
    db.commit()
    db.refresh(booking)
    return booking
