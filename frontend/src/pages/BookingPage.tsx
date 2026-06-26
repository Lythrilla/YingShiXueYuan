import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  api,
  type BookingForm,
  type Resource,
  type ResourceAvailability,
  type Slot,
} from '../api'
import { toDateStr, upcomingDays, WEEKDAYS } from '../lib'

const BOOKING_WINDOW_DAYS = 7

interface SelectedSlot {
  resource: Resource
  slot: Slot
  available: number
}

export default function BookingPage() {
  const days = useMemo(() => upcomingDays(BOOKING_WINDOW_DAYS), [])
  const [date, setDate] = useState(toDateStr(days[0]))
  const [resources, setResources] = useState<Resource[]>([])
  const [slots, setSlots] = useState<Slot[]>([])
  const [availability, setAvailability] = useState<Record<number, ResourceAvailability>>({})
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<SelectedSlot | null>(null)

  useEffect(() => {
    Promise.all([api.get<Resource[]>('/resources'), api.get<Slot[]>('/slots')])
      .then(([r, s]) => {
        setResources(r.data)
        setSlots(s.data)
      })
      .catch(() => {})
  }, [])

  useEffect(() => {
    if (resources.length === 0) return
    setLoading(true)
    Promise.all(
      resources.map((r) =>
        api.get<ResourceAvailability>(`/availability/${r.id}`, { params: { date } }),
      ),
    )
      .then((results) => {
        const map: Record<number, ResourceAvailability> = {}
        results.forEach((res) => {
          map[res.data.resource.id] = res.data
        })
        setAvailability(map)
      })
      .finally(() => setLoading(false))
  }, [resources, date])

  const labs = resources.filter((r) => r.kind === 'lab')
  const equipment = resources.filter((r) => r.kind === 'equipment')

  return (
    <div className="min-h-full pb-16">
      <Hero />

      <main className="mx-auto -mt-20 max-w-5xl px-4">
        <DatePicker days={days} date={date} onChange={setDate} />

        {loading && resources.length === 0 ? (
          <div className="py-20 text-center text-slate-400">加载中…</div>
        ) : (
          <div className="mt-8 space-y-10">
            {labs.length > 0 && (
              <Section title="录音实验室" subtitle="点击下方时段即可预约" icon="lab">
                <div className="grid gap-5 sm:grid-cols-2">
                  {labs.map((r) => (
                    <ResourceCard
                      key={r.id}
                      resource={r}
                      slots={slots}
                      availability={availability[r.id]}
                      onPick={setSelected}
                    />
                  ))}
                </div>
              </Section>
            )}

            {equipment.length > 0 && (
              <Section title="拾音设备" subtitle="可借用的录音设备套装" icon="gear">
                <div className="grid gap-5 sm:grid-cols-2">
                  {equipment.map((r) => (
                    <ResourceCard
                      key={r.id}
                      resource={r}
                      slots={slots}
                      availability={availability[r.id]}
                      onPick={setSelected}
                    />
                  ))}
                </div>
              </Section>
            )}
          </div>
        )}

        <UsageRules />
      </main>

      {selected && (
        <BookingModal
          date={date}
          selected={selected}
          onClose={() => setSelected(null)}
          onSuccess={() => {
            setSelected(null)
            // refresh availability
            api
              .get<ResourceAvailability>(`/availability/${selected.resource.id}`, {
                params: { date },
              })
              .then((res) =>
                setAvailability((prev) => ({ ...prev, [selected.resource.id]: res.data })),
              )
          }}
        />
      )}
    </div>
  )
}

function Hero() {
  return (
    <header className="relative overflow-hidden bg-gradient-to-br from-brand-700 via-brand-600 to-brand-500 pb-28 pt-10 text-white">
      <div className="pointer-events-none absolute -right-16 -top-16 h-64 w-64 rounded-full bg-white/10 blur-2xl" />
      <div className="pointer-events-none absolute -bottom-24 left-10 h-72 w-72 rounded-full bg-brand-300/20 blur-3xl" />
      <div className="mx-auto max-w-5xl px-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-sm font-medium text-white/80">
            <span className="grid h-9 w-9 place-items-center rounded-xl bg-white/15 text-lg">
              🎙️
            </span>
            影视学院 · 录音实验室
          </div>
          <Link
            to="/admin"
            className="rounded-full bg-white/15 px-4 py-1.5 text-sm font-medium text-white backdrop-blur transition hover:bg-white/25"
          >
            后台管理
          </Link>
        </div>
        <div className="mt-10 max-w-2xl animate-fade-up">
          <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">录音实验室预约</h1>
          <p className="mt-3 text-base leading-relaxed text-white/85">
            在线预约录音棚与拾音设备，按时段管理名额，使用完成后由管理员核销。
          </p>
          <p className="mt-4 inline-flex items-center gap-2 rounded-full bg-white/15 px-3.5 py-1.5 text-sm text-white/90">
            <span>🗓️</span> 可提前 {BOOKING_WINDOW_DAYS} 天预约，请按预约时段准时使用
          </p>
        </div>
      </div>
    </header>
  )
}

function DatePicker({
  days,
  date,
  onChange,
}: {
  days: Date[]
  date: string
  onChange: (d: string) => void
}) {
  return (
    <div className="card animate-fade-up p-4">
      <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-slate-700">
        <span className="text-brand-500">🕑</span> 选择日期
      </div>
      <div className="flex gap-2.5 overflow-x-auto pb-1">
        {days.map((d, i) => {
          const ds = toDateStr(d)
          const active = ds === date
          return (
            <button
              key={ds}
              onClick={() => onChange(ds)}
              className={`flex min-w-[68px] flex-col items-center rounded-2xl border px-3 py-2.5 transition ${
                active
                  ? 'border-brand-500 bg-brand-500 text-white shadow-soft'
                  : 'border-slate-200 bg-white text-slate-600 hover:border-brand-300'
              }`}
            >
              <span className={`text-xs ${active ? 'text-white/90' : 'text-slate-400'}`}>
                {i === 0 ? '今天' : WEEKDAYS[d.getDay()]}
              </span>
              <span className="mt-1 text-base font-bold">
                {d.getMonth() + 1}/{d.getDate()}
              </span>
            </button>
          )
        })}
      </div>
    </div>
  )
}

function Section({
  title,
  subtitle,
  icon,
  children,
}: {
  title: string
  subtitle: string
  icon: 'lab' | 'gear'
  children: React.ReactNode
}) {
  return (
    <section className="animate-fade-up">
      <div className="mb-4 flex items-end justify-between">
        <div className="flex items-center gap-3">
          <span className="grid h-10 w-10 place-items-center rounded-xl bg-brand-50 text-xl">
            {icon === 'lab' ? '🎧' : '🎚️'}
          </span>
          <div>
            <h2 className="text-lg font-bold text-slate-800">{title}</h2>
            <p className="text-sm text-slate-400">{subtitle}</p>
          </div>
        </div>
      </div>
      {children}
    </section>
  )
}

function ResourceCard({
  resource,
  slots,
  availability,
  onPick,
}: {
  resource: Resource
  slots: Slot[]
  availability?: ResourceAvailability
  onPick: (s: SelectedSlot) => void
}) {
  const bookable = resource.individual_bookable
  return (
    <div className="card overflow-hidden transition hover:shadow-soft">
      <div className="relative h-36 w-full overflow-hidden bg-gradient-to-br from-brand-100 to-brand-50">
        {resource.image_url ? (
          <img
            src={resource.image_url}
            alt={resource.name}
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="grid h-full place-items-center text-5xl opacity-70">
            {resource.kind === 'lab' ? '🎙️' : '🎛️'}
          </div>
        )}
        <span className="absolute right-3 top-3 rounded-full bg-white/90 px-2.5 py-1 text-xs font-semibold text-brand-600 shadow-sm">
          每时段 {resource.total_quantity} 个名额
        </span>
      </div>
      <div className="p-4">
        <div className="flex items-start justify-between gap-2">
          <h3 className="text-base font-bold text-slate-800">{resource.name}</h3>
        </div>
        <p className="mt-1 line-clamp-2 min-h-[2.5rem] text-sm text-slate-500">
          {resource.description || '暂无描述'}
        </p>

        {!bookable ? (
          <div className="mt-3 rounded-xl bg-slate-50 px-3 py-2.5 text-sm text-slate-400">
            🔒 学生个人不可预约
          </div>
        ) : (
          <div className="mt-3 grid grid-cols-3 gap-2">
            {slots.map((slot) => {
              const sa = availability?.slots.find((x) => x.slot.id === slot.id)
              const avail = sa?.available ?? resource.total_quantity
              const full = avail <= 0
              return (
                <button
                  key={slot.id}
                  disabled={full}
                  onClick={() => onPick({ resource, slot, available: avail })}
                  className={`flex flex-col items-center rounded-xl border px-2 py-2 text-center transition ${
                    full
                      ? 'cursor-not-allowed border-slate-100 bg-slate-50 text-slate-300'
                      : 'border-brand-100 bg-brand-50/50 text-brand-700 hover:border-brand-400 hover:bg-brand-50'
                  }`}
                >
                  <span className="text-sm font-semibold">{slot.name}</span>
                  <span className="text-[11px] text-slate-400">
                    {slot.start_time}-{slot.end_time}
                  </span>
                  <span
                    className={`mt-1 text-[11px] font-medium ${
                      full ? 'text-slate-300' : 'text-emerald-600'
                    }`}
                  >
                    {full ? '已约满' : `剩 ${avail}`}
                  </span>
                </button>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}

function BookingModal({
  date,
  selected,
  onClose,
  onSuccess,
}: {
  date: string
  selected: SelectedSlot
  onClose: () => void
  onSuccess: () => void
}) {
  const { resource, slot } = selected
  const [form, setForm] = useState<BookingForm>({
    resource_id: resource.id,
    slot_id: slot.id,
    date,
    applicant_name: '',
    phone: '',
    major: '',
    num_people: 1,
    instructor: '',
    description: '',
    quantity: 1,
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState(false)

  function update<K extends keyof BookingForm>(key: K, value: BookingForm[K]) {
    setForm((f) => ({ ...f, [key]: value }))
  }

  async function submit() {
    if (!form.applicant_name.trim() || !form.phone.trim()) {
      setError('请填写预约人姓名和联系电话')
      return
    }
    setSubmitting(true)
    setError('')
    try {
      await api.post('/bookings', form)
      setDone(true)
    } catch (err: unknown) {
      const detail =
        (typeof err === 'object' &&
          err &&
          'response' in err &&
          // @ts-expect-error narrow axios error
          err.response?.data?.detail) ||
        '预约失败，请稍后再试'
      setError(String(detail))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-slate-900/40 p-0 backdrop-blur-sm sm:items-center sm:p-4">
      <div className="max-h-[92vh] w-full max-w-lg animate-fade-up overflow-y-auto rounded-t-3xl bg-white p-6 shadow-2xl sm:rounded-3xl">
        {done ? (
          <div className="py-8 text-center">
            <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-emerald-50 text-3xl">
              ✅
            </div>
            <h3 className="mt-4 text-xl font-bold text-slate-800">预约提交成功</h3>
            <p className="mt-2 text-sm text-slate-500">
              {resource.name} · {date} · {slot.name}（{slot.start_time}-{slot.end_time}）
            </p>
            <p className="mt-1 text-sm text-slate-400">请按预约时段准时到场，使用完成后由管理员核销。</p>
            <button className="btn-primary mt-6 w-full" onClick={onSuccess}>
              完成
            </button>
          </div>
        ) : (
          <>
            <div className="flex items-start justify-between">
              <div>
                <h3 className="text-xl font-bold text-slate-800">填写预约信息</h3>
                <p className="mt-1 text-sm text-slate-500">
                  {resource.name} · {date} · {slot.name}（{slot.start_time}-{slot.end_time}）
                </p>
              </div>
              <button
                onClick={onClose}
                className="grid h-9 w-9 place-items-center rounded-full text-slate-400 hover:bg-slate-100"
              >
                ✕
              </button>
            </div>

            <div className="mt-5 grid grid-cols-2 gap-4">
              <Field label="预约人姓名" required>
                <input
                  className="input"
                  value={form.applicant_name}
                  onChange={(e) => update('applicant_name', e.target.value)}
                  placeholder="请输入姓名"
                />
              </Field>
              <Field label="联系电话" required>
                <input
                  className="input"
                  value={form.phone}
                  onChange={(e) => update('phone', e.target.value)}
                  placeholder="手机号"
                />
              </Field>
              <Field label="专业班级">
                <input
                  className="input"
                  value={form.major}
                  onChange={(e) => update('major', e.target.value)}
                  placeholder="如 录音艺术"
                />
              </Field>
              <Field label="指导教师">
                <input
                  className="input"
                  value={form.instructor}
                  onChange={(e) => update('instructor', e.target.value)}
                  placeholder="如 居老师"
                />
              </Field>
              <Field label="录音人数">
                <input
                  type="number"
                  min={1}
                  className="input"
                  value={form.num_people}
                  onChange={(e) => update('num_people', Number(e.target.value) || 1)}
                />
              </Field>
              {resource.kind === 'equipment' && (
                <Field label={`借用数量（剩 ${selected.available}）`}>
                  <input
                    type="number"
                    min={1}
                    max={selected.available}
                    className="input"
                    value={form.quantity}
                    onChange={(e) => update('quantity', Number(e.target.value) || 1)}
                  />
                </Field>
              )}
            </div>
            <div className="mt-4">
              <Field label="录音事项说明">
                <textarea
                  className="input min-h-[84px] resize-none"
                  value={form.description}
                  onChange={(e) => update('description', e.target.value)}
                  placeholder="简要说明录音 / 实验项目内容"
                />
              </Field>
            </div>

            {error && (
              <div className="mt-4 rounded-xl bg-rose-50 px-3.5 py-2.5 text-sm text-rose-600">
                {error}
              </div>
            )}

            <div className="mt-6 flex gap-3">
              <button className="btn-ghost flex-1" onClick={onClose}>
                取消
              </button>
              <button className="btn-primary flex-1" disabled={submitting} onClick={submit}>
                {submitting ? '提交中…' : '确认预约'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function Field({
  label,
  required,
  children,
}: {
  label: string
  required?: boolean
  children: React.ReactNode
}) {
  return (
    <label className="block">
      <span className="label">
        {label}
        {required && <span className="ml-0.5 text-rose-500">*</span>}
      </span>
      {children}
    </label>
  )
}

function UsageRules() {
  return (
    <section className="card mt-10 animate-fade-up p-6">
      <h2 className="flex items-center gap-2 text-base font-bold text-slate-800">
        <span className="text-brand-500">📋</span> 录音实验室使用规定
      </h2>
      <div className="mt-4 grid gap-4 text-sm leading-relaxed text-slate-600 sm:grid-cols-3">
        <div>
          <h3 className="font-semibold text-slate-700">一、使用时间</h3>
          <p className="mt-1 text-slate-500">
            请严格按照预约时间段使用，避免超时影响后续人员。时段已包含设备预热、调试及整理时间。
          </p>
        </div>
        <div>
          <h3 className="font-semibold text-slate-700">二、操作规范</h3>
          <p className="mt-1 text-slate-500">
            使用前请熟悉设备操作规程与安全注意事项，严禁擅自更改设备参数、连接线路或进行非授权操作。
          </p>
        </div>
        <div>
          <h3 className="font-semibold text-slate-700">三、记录与清洁</h3>
          <p className="mt-1 text-slate-500">
            使用后请如实填写设备使用记录，整理麦克风、耳机、线材等设备，关闭电源，保持整洁有序。
          </p>
        </div>
      </div>
    </section>
  )
}
