use rust_xlsxwriter::{Color, Format, FormatAlign, Workbook, XlsxError};

use crate::models::Booking;

const HEADERS: &[&str] = &[
    "预约编号",
    "资源名称",
    "类型",
    "预约日期",
    "时间段",
    "预约人",
    "电话",
    "专业",
    "录音人数",
    "指导教师",
    "数量(套)",
    "状态",
    "提交时间",
    "核销时间",
    "录音事项说明",
];

const WIDTHS: &[f64] = &[
    10.0, 22.0, 8.0, 12.0, 18.0, 12.0, 16.0, 14.0, 10.0, 12.0, 10.0, 10.0, 18.0, 18.0, 40.0,
];

fn status_label(status: &str) -> &str {
    match status {
        "booked" => "已预约",
        "verified" => "已核销",
        "cancelled" => "已取消",
        other => other,
    }
}

/// 把 ISO 时间字符串裁成 "YYYY-MM-DD HH:MM"。
fn fmt_dt(value: &str) -> String {
    if value.len() >= 16 {
        format!("{} {}", &value[0..10], &value[11..16])
    } else {
        value.to_string()
    }
}

pub fn bookings_to_xlsx(bookings: &[Booking]) -> Result<Vec<u8>, XlsxError> {
    let mut workbook = Workbook::new();
    let worksheet = workbook.add_worksheet();
    worksheet.set_name("预约报表")?;

    let header_format = Format::new()
        .set_background_color(Color::RGB(0x4F46E5))
        .set_font_color(Color::White)
        .set_bold()
        .set_align(FormatAlign::Center)
        .set_align(FormatAlign::VerticalCenter);

    for (col, title) in HEADERS.iter().enumerate() {
        worksheet.write_string_with_format(0, col as u16, *title, &header_format)?;
    }

    for (i, b) in bookings.iter().enumerate() {
        let row = (i + 1) as u32;
        let slot_text = format!("{} {}-{}", b.slot.name, b.slot.start_time, b.slot.end_time);
        let kind_text = if b.resource.kind == "lab" {
            "实验室"
        } else {
            "设备"
        };

        worksheet.write_number(row, 0, b.id as f64)?;
        worksheet.write_string(row, 1, &b.resource.name)?;
        worksheet.write_string(row, 2, kind_text)?;
        worksheet.write_string(row, 3, &b.date)?;
        worksheet.write_string(row, 4, &slot_text)?;
        worksheet.write_string(row, 5, &b.applicant_name)?;
        worksheet.write_string(row, 6, &b.phone)?;
        worksheet.write_string(row, 7, &b.major)?;
        worksheet.write_number(row, 8, b.num_people as f64)?;
        worksheet.write_string(row, 9, &b.instructor)?;
        worksheet.write_number(row, 10, b.quantity as f64)?;
        worksheet.write_string(row, 11, status_label(&b.status))?;
        worksheet.write_string(row, 12, fmt_dt(&b.created_at))?;
        worksheet.write_string(
            row,
            13,
            b.verified_at.as_deref().map(fmt_dt).unwrap_or_default(),
        )?;
        worksheet.write_string(row, 14, &b.description)?;
    }

    for (col, width) in WIDTHS.iter().enumerate() {
        worksheet.set_column_width(col as u16, *width)?;
    }
    worksheet.set_freeze_panes(1, 0)?;

    workbook.save_to_buffer()
}
