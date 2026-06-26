export const WEEKDAYS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

export function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

export function toDateStr(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

/** Generate the next `count` days starting today. */
export function upcomingDays(count: number): Date[] {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  return Array.from({ length: count }, (_, i) => {
    const d = new Date(today)
    d.setDate(today.getDate() + i)
    return d
  })
}

export function formatDateTime(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(
    d.getHours(),
  )}:${pad(d.getMinutes())}`
}

export const STATUS_META: Record<
  string,
  { label: string; className: string; dot: string }
> = {
  booked: {
    label: '待核销',
    className: 'bg-amber-50 text-amber-700',
    dot: 'bg-amber-400',
  },
  verified: {
    label: '已核销',
    className: 'bg-emerald-50 text-emerald-700',
    dot: 'bg-emerald-500',
  },
  cancelled: {
    label: '已取消',
    className: 'bg-slate-100 text-slate-500',
    dot: 'bg-slate-400',
  },
}
