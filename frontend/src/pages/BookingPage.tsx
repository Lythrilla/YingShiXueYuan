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
    <div className="min-h-full pb-28">
      <TopNav />
      <Hero />

      <main className="mx-auto max-w-6xl px-6">
        <DatePicker days={days} date={date} onChange={setDate} />

        {loading && resources.length === 0 ? (
          <div className="py-28 text-center text-sm text-ink-400">加载中…</div>
        ) : (
          <div className="mt-16 space-y-20 sm:mt-20 sm:space-y-28">
            {labs.length > 0 && (
              <Section title="录音实验室" subtitle="点击任意时段即可发起预约" kind="lab">
                <div className="grid gap-8 sm:grid-cols-2 sm:gap-10">
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
              <Section title="拾音设备" subtitle="可借用的同期录音设备套装" kind="equipment">
                <div className="grid gap-8 sm:grid-cols-2 sm:gap-10">
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

function TopNav() {
  return (
    <header className="sticky top-0 z-30 border-b border-ink-100/80 bg-white/80 backdrop-blur-xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-3.5">
        <div className="flex items-center gap-2.5">
          <span className="grid h-7 w-7 place-items-center rounded-full bg-ink-900 text-white">
            <MicIcon className="h-3.5 w-3.5" />
          </span>
          <span className="text-[13px] font-medium tracking-tight text-ink-800">
            影视学院 · 录音实验室
          </span>
        </div>
        <Link
          to="/admin"
          className="text-[13px] font-medium text-ink-500 transition hover:text-ink-900"
        >
          后台管理
        </Link>
      </div>
    </header>
  )
}

function Hero() {
  return (
    <section className="mx-auto max-w-4xl px-6 pb-16 pt-20 text-center sm:pb-24 sm:pt-28">
      <p className="eyebrow">Recording Lab · 预约</p>
      <h1 className="display mt-5 text-5xl leading-[1.05] sm:text-7xl">
        录音实验室
        <br className="hidden sm:block" />
        <span className="text-ink-400">随时预约。</span>
      </h1>
      <p className="mx-auto mt-6 max-w-xl text-base leading-relaxed text-ink-500 sm:text-lg">
        四间专业录音棚与同期拾音设备，选择日期与时段，一步完成预约。
      </p>
      <div className="mt-8 inline-flex items-center gap-2 text-[13px] font-medium text-ink-400">
        <CalendarIcon className="h-4 w-4" />
        可提前 {BOOKING_WINDOW_DAYS} 天预约
      </div>
    </section>
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
    <div className="flex justify-center">
      <div className="flex gap-2 overflow-x-auto px-1 pb-1">
        {days.map((d, i) => {
          const ds = toDateStr(d)
          const active = ds === date
          return (
            <button
              key={ds}
              onClick={() => onChange(ds)}
              className={`flex min-w-[64px] flex-col items-center rounded-2xl border px-3 py-2.5 transition ${
                active
                  ? 'border-ink-900 bg-ink-900 text-white'
                  : 'border-ink-200 bg-white text-ink-500 hover:border-ink-300 hover:text-ink-900'
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
      <div className="mb-8 text-center sm:mb-12">
        <span className="mb-4 inline-grid h-9 w-9 place-items-center rounded-full bg-ink-900 text-white">
          {kind === 'lab' ? (
            <HeadphonesIcon className="h-4 w-4" />
          ) : (
            <SlidersIcon className="h-4 w-4" />
          )}
        </span>
        <h2 className="display text-3xl sm:text-4xl">{title}</h2>
        <p className="mt-3 text-[15px] text-ink-400">{subtitle}</p>
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
    <div className="group overflow-hidden rounded-3xl border border-ink-200 bg-white transition duration-200 hover:border-ink-300 hover:shadow-pop">
      <div className="relative aspect-[4/3] w-full overflow-hidden bg-ink-100">
        {resource.image_url ? (
          <img
            src={resource.image_url}
            alt={resource.name}
            loading="lazy"
            className="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]"
          />
        ) : (
          <div className="grid h-full place-items-center text-ink-300">
            {resource.kind === 'lab' ? (
              <MicIcon className="h-12 w-12" />
            ) : (
              <SlidersIcon className="h-12 w-12" />
            )}
          </div>
        )}
        <span className="absolute left-4 top-4 inline-flex items-center gap-1.5 rounded-full bg-white/65 px-3 py-1 text-[11px] font-medium text-ink-800 ring-1 ring-inset ring-white/50 backdrop-blur-md">
          {resource.kind === 'lab' ? (
            <HeadphonesIcon className="h-3 w-3" />
          ) : (
            <SlidersIcon className="h-3 w-3" />
          )}
          {resource.kind === 'lab' ? '实验室' : '设备'}
        </span>
        <span className="absolute right-4 top-4 rounded-full bg-ink-900/50 px-3 py-1 text-[11px] font-medium text-white backdrop-blur-md">
          {resource.total_quantity} 名额
        </span>
      </div>

      <div className="p-6">
        <h3 className="text-xl font-semibold tracking-tight text-ink-900">
          {resource.name}
        </h3>
        <p className="mt-2 line-clamp-2 text-sm leading-relaxed text-ink-500">
          {resource.description || '暂无描述'}
        </p>

      {!bookable ? (
        <div className="mt-5 flex items-center gap-2 rounded-2xl bg-ink-50 px-4 py-3 text-[13px] text-ink-400 ring-1 ring-inset ring-ink-200">
          <LockIcon className="h-4 w-4" /> 学生个人不可预约
        </div>
      ) : (
        <div className="mt-5 grid grid-cols-3 gap-2">
          {slots.map((slot) => {
            const sa = availability?.slots.find((x) => x.slot.id === slot.id)
            const avail = sa?.available ?? resource.total_quantity
            const full = avail <= 0
            return (
              <button
                key={slot.id}
                disabled={full}
                onClick={() => onPick({ resource, slot, available: avail })}
                className={`rounded-2xl border px-3 py-3 text-left transition ${
                  full
                    ? 'cursor-not-allowed border-ink-100 bg-ink-50 text-ink-300'
                    : 'border-ink-200 bg-white text-ink-800 hover:border-ink-900 hover:bg-ink-900 hover:text-white'
                }`}
              >
                <span className="block text-[13px] font-semibold">{slot.name}</span>
                <span className="mt-0.5 block text-[11px] opacity-60">
                  {slot.start_time.slice(0, 5)}
                </span>
                <span className="mt-1.5 block text-[11px] font-medium opacity-80">
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
      <div className="max-h-[92vh] w-full max-w-xl animate-fade-up overflow-y-auto rounded-t-2xl bg-white p-4 shadow-pop sm:rounded-xl sm:p-5">
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

            <div className="mt-5 grid grid-cols-1 gap-3.5 sm:grid-cols-2">
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
                  className="input min-h-[76px] resize-none"
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
    <section className="mt-24 animate-fade-up border-t border-ink-100 pt-16 sm:mt-32 sm:pt-24">
      <div className="mb-10 text-center sm:mb-14">
        <p className="eyebrow">Guidelines</p>
        <h2 className="display mt-4 text-3xl sm:text-4xl">使用规定</h2>
      </div>
      <div className="grid gap-10 sm:grid-cols-3 sm:gap-12">
        {rules.map((r, i) => (
          <div key={r.title} className="text-center">
            <span className="mx-auto grid h-11 w-11 place-items-center rounded-full bg-ink-900 text-sm font-semibold tabular-nums text-white">
              {String(i + 1).padStart(2, '0')}
            </span>
            <h3 className="mt-5 text-base font-semibold text-ink-900">{r.title}</h3>
            <p className="mx-auto mt-2 max-w-xs text-[13px] leading-relaxed text-ink-500">
              {r.body}
            </p>
          </div>
        ))}
      </div>
    </section>
  )
}
