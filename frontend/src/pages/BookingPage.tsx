import { useEffect, useMemo, useState } from 'react'
import {
  api,
  type Booking,
  type BookingForm,
  fetchMyBookings,
  type Resource,
  type ResourceAvailability,
  type Slot,
} from '../api'
import { toDateStr, upcomingDays, WEEKDAYS } from '../lib'
import { isIos, isWeChat, shareApp, useInstallPrompt } from '../pwa'
import {
  CalendarIcon,
  CheckCircleIcon,
  CloseIcon,
  HeadphonesIcon,
  LockIcon,
  MicIcon,
  MinusIcon,
  PhoneAddIcon,
  PlusIcon,
  ShareIcon,
  SlidersIcon,
} from '../icons'

const RULES: { title: string; items: string[] }[] = [
  {
    title: '使用时间',
    items: [
      '请严格按照预约时间段使用录音实验室及相关设备，避免超时影响后续人员的正常使用。',
      '预约时间段已包含设备预热、调试及使用后的整理时间。如需超时，请提前与下一位预约者协商并取得同意。',
    ],
  },
  {
    title: '操作规范',
    items: [
      '使用前请务必熟悉录音设备的操作规程及安全注意事项，包括但不限于调音台、麦克风、音频接口、监听音箱等。',
      '操作过程中请严格遵守实验室及设备的使用规定，严禁擅自更改设备参数、连接线路或进行非授权操作。',
    ],
  },
  {
    title: '记录与清洁',
    items: [
      '使用后请如实填写设备使用记录，内容包括实验 / 录音项目名称、使用设备状态及异常情况等。',
      '使用完毕后，请整理麦克风、耳机、线材等设备，关闭电源，保持录音室及控制室整洁有序。',
    ],
  },
]

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
  const [slotId, setSlotId] = useState<number | null>(null)
  const [availability, setAvailability] = useState<Record<number, ResourceAvailability>>({})
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<SelectedSlot | null>(null)

  useEffect(() => {
    Promise.all([api.get<Resource[]>('/resources'), api.get<Slot[]>('/slots')])
      .then(([r, s]) => {
        setResources(r.data)
        setSlots(s.data)
        setSlotId((cur) => cur ?? s.data[0]?.id ?? null)
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

  const [toast, setToast] = useState('')
  const [rulesAck, setRulesAck] = useState(false)
  const [showMine, setShowMine] = useState(false)

  const slot = slots.find((s) => s.id === slotId) ?? null
  const labs = resources.filter((r) => r.kind === 'lab')
  const equipment = resources.filter((r) => r.kind === 'equipment')

  function availFor(resource: Resource): number {
    if (!slot) return resource.total_quantity
    const sa = availability[resource.id]?.slots.find((x) => x.slot.id === slot.id)
    return sa?.available ?? resource.total_quantity
  }

  const slotRemaining: Record<number, number> = {}
  slots.forEach((s) => {
    let sum = 0
    resources.forEach((r) => {
      if (!r.individual_bookable) return
      const sa = availability[r.id]?.slots.find((x) => x.slot.id === s.id)
      sum += sa?.available ?? r.total_quantity
    })
    slotRemaining[s.id] = sum
  })

  function pick(resource: Resource) {
    if (!slot) return
    setRulesAck(false)
    setSelected({ resource, slot, available: availFor(resource) })
  }

  function closeBooking() {
    setSelected(null)
    setRulesAck(false)
  }

  return (
    <div className="min-h-full bg-ink-50/50 pb-24">
      <TopNav onMine={() => setShowMine(true)} />

      <main className="mx-auto max-w-2xl px-4 py-4 sm:py-5">
        <PageHead />
        <div className="mt-4 space-y-4">
          <TimeSelector
            days={days}
            date={date}
            onDate={setDate}
            slots={slots}
            slotId={slotId}
            onSlot={setSlotId}
            slotRemaining={slotRemaining}
          />

          {loading && resources.length === 0 ? (
            <div className="py-20 text-center text-sm text-ink-400">加载中…</div>
          ) : (
            <>
              {labs.length > 0 && (
                <Section title="录音实验室" subtitle="图片可点击" kind="lab">
                  {labs.map((r) => (
                    <ResourceRow
                      key={r.id}
                      resource={r}
                      available={availFor(r)}
                      hasSlot={!!slot}
                      onPick={pick}
                    />
                  ))}
                </Section>
              )}

              {equipment.length > 0 && (
                <Section title="拾音设备" subtitle="可借用的同期录音设备套装" kind="equipment">
                  {equipment.map((r) => (
                    <ResourceRow
                      key={r.id}
                      resource={r}
                      available={availFor(r)}
                      hasSlot={!!slot}
                      onPick={pick}
                    />
                  ))}
                </Section>
              )}
            </>
          )}
        </div>
      </main>

      <BottomBar onToast={setToast} />
      {showMine && <MyBookings onClose={() => setShowMine(false)} />}
      {toast && <Toast text={toast} onDone={() => setToast('')} />}

      {selected && !rulesAck && (
        <RulesModal onConfirm={() => setRulesAck(true)} onClose={closeBooking} />
      )}

      {selected && rulesAck && (
        <BookingModal
          date={date}
          selected={selected}
          onClose={closeBooking}
          onSuccess={() => {
            closeBooking()
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

function PageHead() {
  return (
    <div className="pt-1">
      <h1 className="text-xl font-semibold tracking-tight text-ink-900">录音实验室预约</h1>
      <p className="mt-1 text-[13px] text-ink-500">河北科技大学影视学院录音系</p>
    </div>
  )
}

function RulesModal({ onConfirm, onClose }: { onConfirm: () => void; onClose: () => void }) {
  const [left, setLeft] = useState(3)
  useEffect(() => {
    if (left <= 0) return
    const t = setTimeout(() => setLeft((v) => v - 1), 1000)
    return () => clearTimeout(t)
  }, [left])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-ink-900/40 backdrop-blur-sm" onClick={onClose} />
      <div className="relative flex max-h-[82vh] w-full max-w-md flex-col overflow-hidden rounded-2xl bg-white shadow-pop">
        <div className="border-b border-ink-100 px-5 py-4 text-center">
          <h3 className="text-base font-semibold text-ink-900">必读须知</h3>
          <p className="mt-0.5 text-[12px] text-ink-400">录音实验室使用规定</p>
        </div>
        <div className="space-y-4 overflow-y-auto px-5 py-4">
          {RULES.map((r, i) => (
            <div key={r.title}>
              <h4 className="text-[13px] font-semibold text-ink-900">
                {['一', '二', '三'][i]}、{r.title}
              </h4>
              <ul className="mt-1.5 space-y-1.5">
                {r.items.map((it, j) => (
                  <li
                    key={it}
                    className="flex gap-1.5 text-[12.5px] leading-relaxed text-ink-500"
                  >
                    <span className="shrink-0 tabular-nums text-ink-400">{j + 1}.</span>
                    <span>{it}</span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
          <p className="rounded-lg bg-ink-50 px-3 py-2 text-[12px] text-ink-400">
            ※ 可提前 {BOOKING_WINDOW_DAYS} 天预约，每日 08:00 开放最新 1 天可约时段
          </p>
        </div>
        <div className="border-t border-ink-100 p-4">
          <button
            className="btn-primary w-full"
            disabled={left > 0}
            onClick={onConfirm}
          >
            {left > 0 ? `已读并确认以上内容（${left}）` : '已读并确认，开始预约'}
          </button>
        </div>
      </div>
    </div>
  )
}

function Toast({ text, onDone }: { text: string; onDone: () => void }) {
  useEffect(() => {
    const t = setTimeout(onDone, 2200)
    return () => clearTimeout(t)
  }, [onDone])
  return (
    <div className="fixed inset-x-0 bottom-24 z-50 flex justify-center px-4">
      <div className="animate-fade-up rounded-full bg-ink-900/90 px-4 py-2 text-[13px] font-medium text-white shadow-pop backdrop-blur">
        {text}
      </div>
    </div>
  )
}

function BottomBar({ onToast }: { onToast: (t: string) => void }) {
  const { installed, promptInstall } = useInstallPrompt()
  const [guide, setGuide] = useState<'share' | 'install' | null>(null)

  async function onShare() {
    const r = await shareApp()
    if (r.status === 'wechat') setGuide('share')
    else if (r.status === 'copied') onToast('链接已复制，可粘贴到其他应用分享')
    else if (r.status === 'unavailable') onToast('当前环境不支持分享')
  }

  async function onInstall() {
    if (isWeChat()) {
      setGuide('install')
      return
    }
    const r = await promptInstall()
    if (r === 'unavailable') {
      onToast(
        isIos()
          ? '请点击底部「分享」图标，选择「添加到主屏幕」'
          : '请在浏览器菜单选择「添加到主屏幕 / 安装」',
      )
    }
  }

  return (
    <>
      <div className="fixed inset-x-0 bottom-0 z-40 border-t border-ink-200 bg-white/90 backdrop-blur-xl">
        <div className="mx-auto flex max-w-2xl items-center gap-2.5 px-4 py-2.5 pb-[calc(0.625rem+env(safe-area-inset-bottom))]">
          <button className="btn-ghost flex-1" onClick={onShare}>
            <ShareIcon className="h-4 w-4" /> 分享
          </button>
          {!installed && (
            <button className="btn-primary flex-1" onClick={onInstall}>
              <PhoneAddIcon className="h-4 w-4" /> 加入桌面
            </button>
          )}
        </div>
      </div>
      {guide && <WeChatGuide mode={guide} onClose={() => setGuide(null)} />}
    </>
  )
}

/**
 * WeChat's in-app browser blocks Web Share and PWA install, so we guide the
 * user to the top-right "···" menu instead.
 */
function WeChatGuide({ mode, onClose }: { mode: 'share' | 'install'; onClose: () => void }) {
  const steps =
    mode === 'share'
      ? ['点击右上角的「···」菜单', '选择「发送给朋友」或「分享到朋友圈」']
      : ['点击右上角的「···」菜单', '选择「在浏览器打开」', '在浏览器中再「添加到主屏幕」']

  return (
    <div
      className="fixed inset-0 z-50 bg-ink-900/70 backdrop-blur-sm"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
    >
      <div className="flex justify-end px-5 pt-4 text-white" onClick={(e) => e.stopPropagation()}>
        <div className="text-right">
          <div className="text-3xl leading-none">···</div>
          <div className="mt-1 text-sm">请点这里</div>
          <div className="ml-auto mt-1 h-10 w-px bg-white/70" />
        </div>
      </div>
      <div
        className="absolute inset-x-0 bottom-0 rounded-t-3xl bg-white px-6 pb-[calc(1.5rem+env(safe-area-inset-bottom))] pt-6"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mx-auto max-w-md">
          <div className="flex items-center justify-between">
            <h3 className="text-base font-semibold text-ink-900">
              {mode === 'share' ? '在微信中分享' : '添加到桌面'}
            </h3>
            <button className="text-ink-400" onClick={onClose} aria-label="关闭">
              <CloseIcon className="h-5 w-5" />
            </button>
          </div>
          <p className="mt-1 text-[13px] text-ink-500">
            微信浏览器不支持直接{mode === 'share' ? '分享' : '添加桌面'}，请按下面步骤操作：
          </p>
          <ol className="mt-4 space-y-3">
            {steps.map((s, i) => (
              <li key={i} className="flex items-center gap-3">
                <span className="grid h-6 w-6 flex-none place-items-center rounded-full bg-ink-900 text-xs font-semibold text-white">
                  {i + 1}
                </span>
                <span className="text-sm text-ink-700">{s}</span>
              </li>
            ))}
          </ol>
          <button className="btn-primary mt-6 w-full" onClick={onClose}>
            我知道了
          </button>
        </div>
      </div>
    </div>
  )
}

function TopNav({ onMine }: { onMine: () => void }) {
  return (
    <header className="sticky top-0 z-30 border-b border-ink-200 bg-white/85 backdrop-blur-xl">
      <div className="mx-auto flex max-w-2xl items-center gap-2.5 px-4 py-3">
        <span className="grid h-7 w-7 place-items-center rounded-full bg-ink-900 text-white">
          <MicIcon className="h-3.5 w-3.5" />
        </span>
        <span className="text-[13px] font-medium tracking-tight text-ink-800">
          影视学院 · 录音系
        </span>
        <button
          className="ml-auto flex items-center gap-1 rounded-full border border-ink-200 px-3 py-1.5 text-[13px] font-medium text-ink-700 active:bg-ink-50"
          onClick={onMine}
        >
          <CalendarIcon className="h-3.5 w-3.5" /> 我的预约
        </button>
      </div>
    </header>
  )
}

const STATUS_META: Record<Booking['status'], { label: string; cls: string }> = {
  booked: { label: '待核销', cls: 'bg-amber-100 text-amber-700' },
  verified: { label: '已核销', cls: 'bg-emerald-100 text-emerald-700' },
  cancelled: { label: '已取消', cls: 'bg-ink-100 text-ink-400' },
}

/** 「我的预约」弹层：按手机号查询本人预约，手机号通过 Cookie 记住。 */
function MyBookings({ onClose }: { onClose: () => void }) {
  const [phone, setPhone] = useState('')
  const [bookings, setBookings] = useState<Booking[] | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function query(p?: string) {
    setLoading(true)
    setError('')
    try {
      const data = await fetchMyBookings(p)
      setBookings(data)
    } catch {
      setError('查询失败，请检查手机号后重试')
      setBookings(null)
    } finally {
      setLoading(false)
    }
  }

  // 首次打开时若 Cookie 里记住了手机号，自动查询。
  useEffect(() => {
    const remembered = document.cookie
      .split(';')
      .map((c) => c.trim())
      .find((c) => c.startsWith('mine_phone='))
      ?.split('=')[1]
    if (remembered) {
      const p = decodeURIComponent(remembered)
      setPhone(p)
      void query(p)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="fixed inset-0 z-50 bg-ink-900/60 backdrop-blur-sm" onClick={onClose}>
      <div
        className="absolute inset-x-0 bottom-0 flex max-h-[85vh] flex-col rounded-t-3xl bg-white"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-ink-100 px-6 py-4">
          <h3 className="text-base font-semibold text-ink-900">我的预约</h3>
          <button className="text-ink-400" onClick={onClose} aria-label="关闭">
            <CloseIcon className="h-5 w-5" />
          </button>
        </div>

        <div className="flex items-center gap-2 px-6 py-3">
          <input
            className="input flex-1"
            type="tel"
            inputMode="numeric"
            placeholder="输入预约手机号查询"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && phone.trim() && query(phone.trim())}
          />
          <button
            className="btn-primary"
            disabled={!phone.trim() || loading}
            onClick={() => query(phone.trim())}
          >
            查询
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-6 pb-[calc(1.5rem+env(safe-area-inset-bottom))]">
          {error && <p className="py-2 text-[13px] text-rose-500">{error}</p>}
          {loading && <p className="py-6 text-center text-sm text-ink-400">查询中…</p>}
          {!loading && bookings && bookings.length === 0 && (
            <p className="py-10 text-center text-sm text-ink-400">没有查询到预约记录</p>
          )}
          {!loading && bookings && bookings.length > 0 && (
            <ul className="space-y-2.5 py-1">
              {bookings.map((b) => {
                const meta = STATUS_META[b.status]
                return (
                  <li key={b.id} className="rounded-2xl border border-ink-100 p-3.5">
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-medium text-ink-900">{b.resource.name}</span>
                      <span className={`rounded-full px-2 py-0.5 text-xs ${meta.cls}`}>
                        {meta.label}
                      </span>
                    </div>
                    <div className="mt-1.5 text-[13px] text-ink-500">
                      {b.date} · {b.slot.name}（{b.slot.start_time}-{b.slot.end_time}）
                    </div>
                    <div className="mt-0.5 text-[13px] text-ink-400">
                      {b.applicant_name} · 数量 {b.quantity}
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </div>
      </div>
    </div>
  )
}

function TimeSelector({
  days,
  date,
  onDate,
  slots,
  slotId,
  onSlot,
  slotRemaining,
}: {
  days: Date[]
  date: string
  onDate: (d: string) => void
  slots: Slot[]
  slotId: number | null
  onSlot: (id: number) => void
  slotRemaining: Record<number, number>
}) {
  return (
    <section className="card p-4">
      <div className="mb-3 flex items-center gap-2 text-sm font-medium text-ink-800">
        <CalendarIcon className="h-4 w-4 text-ink-400" /> 选择时间
      </div>

      <div className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
        {days.map((d, i) => {
          const ds = toDateStr(d)
          const active = ds === date
          return (
            <button
              key={ds}
              onClick={() => onDate(ds)}
              className={`flex min-w-[60px] shrink-0 flex-col items-center rounded-xl border px-3 py-2 transition ${
                active
                  ? 'border-ink-900 bg-ink-900 text-white'
                  : 'border-ink-200 bg-white text-ink-500 hover:border-ink-300 hover:text-ink-900'
              }`}
            >
              <span className={`text-[11px] ${active ? 'text-white/70' : 'text-ink-400'}`}>
                {i === 0 ? '今天' : WEEKDAYS[d.getDay()]}
              </span>
              <span className="mt-0.5 text-sm font-semibold tracking-tight">
                {d.getMonth() + 1}/{d.getDate()}
              </span>
            </button>
          )
        })}
      </div>

      <div className="mt-3 grid grid-cols-3 gap-2.5 border-t border-ink-100 pt-3.5">
        {slots.map((s) => {
          const active = s.id === slotId
          const left = slotRemaining[s.id] ?? 0
          const full = left <= 0
          return (
            <button
              key={s.id}
              onClick={() => onSlot(s.id)}
              className={`rounded-xl border px-2 py-3 text-center transition ${
                active
                  ? 'border-ink-900 bg-ink-50 ring-1 ring-ink-900'
                  : 'border-ink-200 bg-white hover:border-ink-300'
              }`}
            >
              <span className="block text-[13px] font-semibold tabular-nums text-ink-900">
                {s.start_time.slice(0, 5)} ~ {s.end_time.slice(0, 5)}
              </span>
              <span
                className={`mt-1 block text-[12px] font-medium ${full ? 'text-ink-400' : 'text-sky-600'}`}
              >
                {full ? '已约满' : `剩余 ${left}`}
              </span>
            </button>
          )
        })}
      </div>

      <p className="mt-3 text-[12px] text-ink-400">
        ※ 可提前 {BOOKING_WINDOW_DAYS} 天预约，每日 08:00 开放最新 1 天可约时段
      </p>
    </section>
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
      <div className="mb-2.5 flex items-center gap-2 px-0.5">
        <span className="grid h-6 w-6 place-items-center rounded-md bg-ink-900 text-white">
          {kind === 'lab' ? (
            <HeadphonesIcon className="h-3.5 w-3.5" />
          ) : (
            <SlidersIcon className="h-3.5 w-3.5" />
          )}
        </span>
        <h2 className="text-[15px] font-semibold tracking-tight text-ink-900">{title}</h2>
        <span className="text-[12px] text-ink-400">{subtitle}</span>
      </div>
      <div className="space-y-3">{children}</div>
    </section>
  )
}

function ResourceRow({
  resource,
  available,
  hasSlot,
  onPick,
}: {
  resource: Resource
  available: number
  hasSlot: boolean
  onPick: (r: Resource) => void
}) {
  const bookable = resource.individual_bookable
  const full = available <= 0
  const disabled = !bookable || !hasSlot || full
  const status = !bookable ? '不可预约' : !hasSlot ? '请选时段' : full ? '已约满' : `剩 ${available}`

  return (
    <button
      type="button"
      disabled={disabled}
      onClick={() => onPick(resource)}
      className={`card flex w-full items-center gap-3 p-3 text-left transition ${
        disabled ? 'opacity-70' : 'hover:border-ink-300 hover:shadow-pop'
      }`}
    >
      <div className="h-[68px] w-[92px] shrink-0 overflow-hidden rounded-lg bg-ink-100">
        {resource.image_url ? (
          <img
            src={resource.image_url}
            alt={resource.name}
            loading="lazy"
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="grid h-full place-items-center text-ink-300">
            {resource.kind === 'lab' ? (
              <MicIcon className="h-6 w-6" />
            ) : (
              <SlidersIcon className="h-6 w-6" />
            )}
          </div>
        )}
      </div>

      <div className="min-w-0 flex-1">
        <h3 className="truncate text-[15px] font-semibold tracking-tight text-ink-900">
          {resource.name}
        </h3>
        <p className="mt-1 line-clamp-2 text-[12.5px] leading-relaxed text-ink-500">
          {resource.description || '暂无描述'}
        </p>
        {!bookable && (
          <span className="mt-1 inline-flex items-center gap-1 text-[11px] text-ink-400">
            <LockIcon className="h-3 w-3" /> 需指导老师带领使用
          </span>
        )}
      </div>

      <div className="flex shrink-0 flex-col items-end gap-1.5">
        <span
          className={`text-[12px] font-medium tabular-nums ${
            !bookable || full ? 'text-ink-400' : 'text-ink-700'
          }`}
        >
          {status}
        </span>
        <span
          className={`rounded-full px-3 py-1 text-[12px] font-medium ${
            disabled ? 'bg-ink-100 text-ink-400' : 'bg-ink-900 text-white'
          }`}
        >
          预约
        </span>
      </div>
    </button>
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
                <Stepper
                  value={form.num_people}
                  min={1}
                  max={50}
                  onChange={(v) => update('num_people', v)}
                />
              </Field>
              {resource.kind === 'equipment' && (
                <Field label={`借用数量（剩 ${selected.available}）`}>
                  <Stepper
                    value={form.quantity}
                    min={1}
                    max={selected.available}
                    onChange={(v) => update('quantity', v)}
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

function Stepper({
  value,
  min,
  max,
  onChange,
}: {
  value: number
  min: number
  max: number
  onChange: (v: number) => void
}) {
  const clamp = (v: number) => Math.max(min, Math.min(max, v))
  return (
    <div className="inline-flex items-center rounded-lg border border-ink-200 bg-white">
      <button
        type="button"
        onClick={() => onChange(clamp(value - 1))}
        disabled={value <= min}
        className="grid h-9 w-9 place-items-center rounded-l-lg text-ink-600 transition hover:bg-ink-50 disabled:opacity-40"
        aria-label="减少"
      >
        <MinusIcon className="h-4 w-4" />
      </button>
      <span className="w-12 text-center text-sm font-semibold tabular-nums text-ink-900">
        {value}
      </span>
      <button
        type="button"
        onClick={() => onChange(clamp(value + 1))}
        disabled={value >= max}
        className="grid h-9 w-9 place-items-center rounded-r-lg text-ink-600 transition hover:bg-ink-50 disabled:opacity-40"
        aria-label="增加"
      >
        <PlusIcon className="h-4 w-4" />
      </button>
    </div>
  )
}
