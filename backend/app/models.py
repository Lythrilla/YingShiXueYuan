from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


class Resource(Base):
    """实验室或设备资源。"""

    __tablename__ = "resources"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    # "lab" = 实验室 / 棚, "equipment" = 设备套装
    kind: Mapped[str] = mapped_column(String(20), default="lab")
    description: Mapped[str] = mapped_column(Text, default="")
    image_url: Mapped[str] = mapped_column(String(500), default="")
    # 每个时段可同时预约的数量（实验室一般为 1，基础设备 5，进阶设备 1）
    total_quantity: Mapped[int] = mapped_column(Integer, default=1)
    # 学生个人是否可预约（全景声棚为 False）
    individual_bookable: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    bookings: Mapped[list["Booking"]] = relationship(back_populates="resource")


class TimeSlot(Base):
    """可预约的时间段（上午 / 下午 / 晚上）。"""

    __tablename__ = "time_slots"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(40), nullable=False)
    start_time: Mapped[str] = mapped_column(String(10), nullable=False)  # "08:00"
    end_time: Mapped[str] = mapped_column(String(10), nullable=False)  # "12:00"
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class Booking(Base):
    """一条预约记录。"""

    __tablename__ = "bookings"

    id: Mapped[int] = mapped_column(primary_key=True)
    resource_id: Mapped[int] = mapped_column(ForeignKey("resources.id"), nullable=False)
    slot_id: Mapped[int] = mapped_column(ForeignKey("time_slots.id"), nullable=False)
    date: Mapped[str] = mapped_column(String(10), nullable=False)  # "2026-06-26"

    applicant_name: Mapped[str] = mapped_column(String(60), nullable=False)
    phone: Mapped[str] = mapped_column(String(40), nullable=False)
    major: Mapped[str] = mapped_column(String(80), default="")
    num_people: Mapped[int] = mapped_column(Integer, default=1)
    instructor: Mapped[str] = mapped_column(String(60), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    quantity: Mapped[int] = mapped_column(Integer, default=1)  # 设备套数

    # "booked" 已预约 / "verified" 已核销 / "cancelled" 已取消
    status: Mapped[str] = mapped_column(String(20), default="booked")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    resource: Mapped["Resource"] = relationship(back_populates="bookings")
    slot: Mapped["TimeSlot"] = relationship()
