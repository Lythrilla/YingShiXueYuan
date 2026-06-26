from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import Resource, TimeSlot

DEFAULT_SLOTS = [
    {"name": "上午", "start_time": "08:00", "end_time": "12:00", "sort_order": 1},
    {"name": "下午", "start_time": "12:00", "end_time": "18:00", "sort_order": 2},
    {"name": "晚上", "start_time": "18:00", "end_time": "23:00", "sort_order": 3},
]

# 默认资源，来自需求文档
DEFAULT_RESOURCES = [
    {
        "name": "全景声棚",
        "kind": "lab",
        "description": "沉浸式全景声录音棚。学生个人不可预约，需在指导老师带领下使用；面向外部录音借用开放。",
        "total_quantity": 1,
        "individual_bookable": False,
        "sort_order": 1,
    },
    {
        "name": "5.1 编辑室",
        "kind": "lab",
        "description": "5.1 声道音频编辑制作工作室。",
        "total_quantity": 1,
        "individual_bookable": True,
        "sort_order": 2,
    },
    {
        "name": "拟音棚",
        "kind": "lab",
        "description": "用于拟音（Foley）录制的专业棚。",
        "total_quantity": 1,
        "individual_bookable": True,
        "sort_order": 3,
    },
    {
        "name": "5.1 终混棚",
        "kind": "lab",
        "description": "5.1 环绕声终混录音棚。",
        "total_quantity": 1,
        "individual_bookable": True,
        "sort_order": 4,
    },
    {
        "name": "同期拾音设备基础套装",
        "kind": "equipment",
        "description": "同期录音基础设备套装，共 5 套可供借用。",
        "total_quantity": 5,
        "individual_bookable": True,
        "sort_order": 5,
    },
    {
        "name": "同期拾音设备进阶套装",
        "kind": "equipment",
        "description": "同期录音高端进阶设备套装，仅 1 套，需注明整体使用时间。",
        "total_quantity": 1,
        "individual_bookable": True,
        "sort_order": 6,
    },
]


def seed(db: Session) -> None:
    if not db.scalars(select(TimeSlot)).first():
        for s in DEFAULT_SLOTS:
            db.add(TimeSlot(**s))
    if not db.scalars(select(Resource)).first():
        for r in DEFAULT_RESOURCES:
            db.add(Resource(**r))
    db.commit()
