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
import {
  CalendarIcon,
  CheckCircleIcon,
  CloseIcon,
  HeadphonesIcon,
  LockIcon,
  MicIcon,
  SlidersIcon,
} from '../icons'

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
    <div className="min-h-full pb-20">
      <Hero />

      <main className="mx-auto -mt-16 max-w-5xl px-5">
        <DatePicker days={days} date={date} onChange={setDate} />

        {loading && resources.length === 0 ? (
          <div className="py-24 text-center text-sm text-ink-400">加载中…</div>
        ) : (
          <div className="mt-12 space-y-12">
            {labs.length > 0 && (
              <Section title="录音实验室" subtitle="点击时段即可发起预约" kind="lab">
                <div className="grid gap-4 sm:grid-cols-2">
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
              <Section title="拾音设备" subtitle="可借用的录音设备套装" kind="equipment">
                <div className="grid gap-4 sm:grid-cols-2">
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
    <header className="relative overflow-hidden bg-ink-950 pb-24 pt-7 text-white">
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.07]"
        style={{
          backgroundImage:
            'linear-gradient(to right, white 1px, transparent 1px), linear-gradient(to bottom, white 1px, transparent 1px)',
          backgroundSize: '46px 46px',
        }}
      />
      <div className="pointer-events-none absolute -right-20 -top-24 h-72 w-72 rounded-full bg-accent-500/20 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-28 left-1/4 h-72 w-72 rounded-full bg-accent-400/10 blur-3xl" />

      <div className="relative mx-auto max-w-5xl px-5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <span className="grid h-9 w-9 place-items-center rounded-xl bg-white/10 ring-1 ring-white/15">
              <MicIcon className="h-[18px] w-[18px] text-white" />
            </span>
            <span className="text-sm font-medium tracking-tight text-white/85">
              影视学院 · 录音实验室
            </span>
          </div>
          <Link
            to="/admin"
            className="rounded-full px-3.5 py-1.5 text-sm font-medium text-white/75 ring-1 ring-white/15 transition hover:bg-white/10 hover:text-white"
          >
            后台管理
          </Link>
        </div>

        <div className="mt-14 max-w-2xl animate-fade-up">
          <p className="eyebrow text-white/45">Recording Lab · Online Booking</p>
          <h1 className="mt-3 text-4xl font-semibold tracking-tight sm:text-[2.7rem] sm:leading-[1.1]">
            录音实验室预约
          </h1>
          <p className="mt-4 max-w-xl text-[15px] leading-relaxed text-white/65">
            在线预约录音棚与拾音设备，按时段管理名额，使用完成后由管理员核销。
          </p>
          <div className="mt-6 inline-flex items-center gap-2 rounded-full bg-white/8 px-3.5 py-1.5 text-[13px] text-white/70 ring-1 ring-white/10">
            <CalendarIcon className="h-4 w-4" />
            可提前 {BOOKING_WINDOW_DAYS} 天预约，请按时段准时使用
          </div>
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
    <div className="card animate-fade-up p-4 sm:p-5">
      <div className="mb-3.5 flex items-center gap-2 text-[13px] font-medium text-ink-500">
        <CalendarIcon className="h-4 w-4 text-ink-400" /> 选择日期
      </div>
      <div className="flex gap-2 overflow-x-auto pb-1">
        {days.map((d, i) => {
          const ds = toDateStr(d)
          const active = ds === date
          return (
            <button
              key={ds}
              onClick={() => onChange(ds)}
              className={`flex min-w-[66px] flex-col items-center rounded-xl border px-3 py-2.5 transition ${
                active
                  ? 'border-ink-950 bg-ink-950 text-white shadow-soft'
                  : 'border-ink-200 bg-white text-ink-600 hover:border-ink-300 hover:bg-ink-50'
              }`}
            >
              <span className={`text-[11px] ${active ? 'text-white/70' : 'text-ink-400'}`}>
                {i === 0 ? '今天' : WEEKDAYS[d.getDay()]}
              </span>
              <span className="mt-1 text-[15px] font-semibold tracking-tight">
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
  kind,
  children,
}: {
  title: string
  subtitle: string
  kind: 'lab' | 'equipment'
  children: React.ReactNode
}) {
  return (
    <section className="animate-fade-up">
      <div className="mb-5 flex items-center gap-3">
        <span className="grid h-10 w-10 place-items-center rounded-xl bg-white text-ink-700 shadow-card ring-1 ring-ink-200/70">
          {kind === 'lab' ? (
            <HeadphonesIcon className="h-5 w-5" />
          ) : (
            <SlidersIcon className="h-5 w-5" />
          )}
        </span>
        <div>
          <h2 className="text-[17px] font-semibold tracking-tight text-ink-900">{title}</h2>
          <p className="text-[13px] text-ink-400">{subtitle}</p>
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
    <div className="card overflow-hidden transition duration-200 hover:-translate-y-0.5 hover:shadow-soft">
      <div className="relative h-32 w-full overflow-hidden bg-ink-100">
        {resource.image_url ? (
          <img
            src={resource.image_url}
            alt={resource.name}
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="grid h-full place-items-center bg-gradient-to-br from-ink-100 to-ink-200/60 text-ink-300">
            {resource.kind === 'lab' ? (
              <MicIcon className="h-9 w-9" />
            ) : (
              <SlidersIcon className="h-9 w-9" />
            )}
          </div>
        )}
        <span className="absolute right-3 top-3 rounded-full bg-white/95 px-2.5 py-1 text-[11px] font-medium text-ink-600 shadow-sm ring-1 ring-ink-200/60 backdrop-blur">
          每时段 {resource.total_quantity} 个名额
        </span>
      </div>
      <div className="p-4">
        <h3 className="text-[15px] font-semibold tracking-tight text-ink-900">{resource.name}</h3>
        <p className="mt-1 line-clamp-2 min-h-[2.5rem] text-[13px] leading-relaxed text-ink-500">
          {resource.description || '暂无描述'}
        </p>

        {!bookable ? (
          <div className="mt-3 flex items-center gap-2 rounded-xl bg-ink-50 px-3 py-2.5 text-[13px] text-ink-400 ring-1 ring-inset ring-ink-200/60">
            <LockIcon className="h-4 w-4" /> 学生个人不可预约
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
                  className={`flex flex-col items-center rounded-xl border px-2 py-2.5 text-center transition ${
                    full
                      ? 'cursor-not-allowed border-ink-100 bg-ink-50 text-ink-300'
                      : 'border-ink-200 bg-white text-ink-700 hover:border-ink-950 hover:bg-ink-50'
                  }`}
                >
                  <span className="text-[13px] font-semibold">{slot.name}</span>
                  <span className="text-[11px] text-ink-400">
                    {slot.start_time}-{slot.end_time}
                  </span>
                  <span
                    className={`mt-1 text-[11px] font-medium ${
                      full ? 'text-ink-300' : 'text-emerald-600'
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
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink-950/45 p-0 backdrop-blur-sm animate-fade-in sm:items-center sm:p-4">
      <div className="max-h-[92vh] w-full max-w-lg animate-fade-up overflow-y-auto rounded-t-3xl bg-white p-6 shadow-pop sm:rounded-2xl">
        {done ? (
          <div className="py-8 text-center">
            <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-emerald-50 text-emerald-600 ring-1 ring-emerald-100">
              <CheckCircleIcon className="h-7 w-7" />
            </div>
            <h3 className="mt-4 text-lg font-semibold tracking-tight text-ink-900">预约提交成功</h3>
            <p className="mt-2 text-sm text-ink-500">
              {resource.name} · {date} · {slot.name}（{slot.start_time}-{slot.end_time}）
            </p>
            <p className="mt-1 text-[13px] text-ink-400">
              请按预约时段准时到场，使用完成后由管理员核销。
            </p>
            <button className="btn-primary mt-6 w-full" onClick={onSuccess}>
              完成
            </button>
          </div>
        ) : (
          <>
            <div className="flex items-start justify-between">
              <div>
                <p className="eyebrow">填写预约信息</p>
                <h3 className="mt-1.5 text-lg font-semibold tracking-tight text-ink-900">
                  {resource.name}
                </h3>
                <p className="mt-0.5 text-[13px] text-ink-500">
                  {date} · {slot.name}（{slot.start_time}-{slot.end_time}）
                </p>
              </div>
              <button
                onClick={onClose}
                className="grid h-9 w-9 place-items-center rounded-full text-ink-400 transition hover:bg-ink-100 hover:text-ink-700"
              >
                <CloseIcon className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-6 grid grid-cols-2 gap-4">
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
              <div className="mt-4 rounded-xl bg-rose-50 px-3.5 py-2.5 text-[13px] text-rose-600 ring-1 ring-inset ring-rose-100">
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
  const rules = [
    {
      title: '使用时间',
      body: '请严格按照预约时间段使用，避免超时影响后续人员。时段已包含设备预热、调试及整理时间。',
    },
    {
      title: '操作规范',
      body: '使用前请熟悉设备操作规程与安全注意事项，严禁擅自更改设备参数、连接线路或进行非授权操作。',
    },
    {
      title: '记录与清洁',
      body: '使用后请如实填写设备使用记录，整理麦克风、耳机、线材等设备，关闭电源，保持整洁有序。',
    },
  ]
  return (
    <section className="mt-14 animate-fade-up">
      <div className="mb-5 flex items-center justify-between">
        <div>
          <p className="eyebrow">Guidelines</p>
          <h2 className="mt-1.5 text-[17px] font-semibold tracking-tight text-ink-900">
            录音实验室使用规定
          </h2>
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-3">
        {rules.map((r, i) => (
          <div key={r.title} className="card p-5">
            <span className="text-sm font-semibold tabular-nums text-ink-300">
              {String(i + 1).padStart(2, '0')}
            </span>
            <h3 className="mt-2 text-sm font-semibold text-ink-800">{r.title}</h3>
            <p className="mt-1.5 text-[13px] leading-relaxed text-ink-500">{r.body}</p>
          </div>
        ))}
      </div>
    </section>
  )
}
