from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


# ---------- Resource ----------
class ResourceBase(BaseModel):
    name: str
    kind: str = "lab"
    description: str = ""
    image_url: str = ""
    total_quantity: int = 1
    individual_bookable: bool = True
    sort_order: int = 0
    is_active: bool = True


class ResourceCreate(ResourceBase):
    pass


class ResourceUpdate(BaseModel):
    name: str | None = None
    kind: str | None = None
    description: str | None = None
    image_url: str | None = None
    total_quantity: int | None = None
    individual_bookable: bool | None = None
    sort_order: int | None = None
    is_active: bool | None = None


class ResourceOut(ResourceBase):
    model_config = ConfigDict(from_attributes=True)
    id: int


# ---------- TimeSlot ----------
class SlotBase(BaseModel):
    name: str
    start_time: str
    end_time: str
    sort_order: int = 0
    is_active: bool = True


class SlotCreate(SlotBase):
    pass


class SlotUpdate(BaseModel):
    name: str | None = None
    start_time: str | None = None
    end_time: str | None = None
    sort_order: int | None = None
    is_active: bool | None = None


class SlotOut(SlotBase):
    model_config = ConfigDict(from_attributes=True)
    id: int


# ---------- Availability ----------
class SlotAvailability(BaseModel):
    slot: SlotOut
    total_quantity: int
    booked_quantity: int
    available: int


class ResourceAvailability(BaseModel):
    resource: ResourceOut
    date: str
    slots: list[SlotAvailability]


# ---------- Booking ----------
class BookingCreate(BaseModel):
    resource_id: int
    slot_id: int
    date: str
    applicant_name: str = Field(min_length=1)
    phone: str = Field(min_length=1)
    major: str = ""
    num_people: int = 1
    instructor: str = ""
    description: str = ""
    quantity: int = 1


class BookingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    resource_id: int
    slot_id: int
    date: str
    applicant_name: str
    phone: str
    major: str
    num_people: int
    instructor: str
    description: str
    quantity: int
    status: str
    created_at: datetime
    verified_at: datetime | None
    resource: ResourceOut
    slot: SlotOut


# ---------- Auth ----------
class LoginRequest(BaseModel):
    username: str
    password: str


class TokenOut(BaseModel):
    token: str
    username: str
