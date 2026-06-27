import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  api,
  clearToken,
  getToken,
  setToken,
  uploadImage,
  type Booking,
  type Resource,
  type Slot,
  type Stats,
} from '../api'
import { formatDateTime, STATUS_META, toDateStr } from '../lib'
import {
  ArrowLeftIcon,
  CloseIcon,
  DownloadIcon,
  HomeIcon,
  ImageIcon,
  LogoutIcon,
  MicIcon,
  PlusIcon,
  SearchIcon,
  UploadIcon,
} from '../icons'

type Tab = 'overview' | 'bookings' | 'resources' | 'slots'

export default function AdminPage() {
  const [authed, setAuthed] = useState(!!getToken())

  if (!authed) return <Login onSuccess={() => setAuthed(true)} />
  return <Dashboard onLogout={() => setAuthed(false)} />
}

function Login({ onSuccess }: { onSuccess: () => void }) {
  const [username, setUsername] = useState('admin')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError('')
    try {
      const res = await api.post('/admin/login', { username, password })
      setToken(res.data.token)
      onSuccess()
    } catch {
      setError('用户名或密码错误')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="grid min-h-full place-items-center bg-ink-50 p-4">
      <form
        onSubmit={submit}
        className="w-full max-w-sm animate-fade-up rounded-xl border border-ink-200 bg-white p-8 shadow-soft"
      >
        <div className="grid h-11 w-11 place-items-center rounded-2xl bg-ink-900 text-white">
          <MicIcon className="h-6 w-6" />
        </div>
        <h1 className="mt-5 text-xl font-semibold tracking-tight text-ink-900">录音系预约后台</h1>
        <p className="mt-1 text-[13px] text-ink-400">河北科技大学影视学院录音系</p>

        <div className="mt-7 space-y-4">
          <label className="block">
            <span className="label">用户名</span>
            <input
              className="input"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
            />
          </label>
          <label className="block">
            <span className="label">密码</span>
            <input
              type="password"
              className="input"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="请输入密码"
            />
          </label>
        </div>

        {error && (
          <div className="mt-4 rounded-xl bg-rose-50 px-3.5 py-2.5 text-[13px] text-rose-600 ring-1 ring-inset ring-rose-100">
            {error}
          </div>
        )}

        <button className="btn-primary mt-6 w-full" disabled={loading}>
          {loading ? '登录中…' : '登录'}
        </button>
        <Link
          to="/"
          className="mt-5 flex items-center justify-center gap-1.5 text-[13px] text-ink-400 transition hover:text-ink-700"
        >
          <ArrowLeftIcon className="h-4 w-4" /> 返回预约首页
        </Link>
      </form>
    </div>
  )
}

const TABS: [Tab, string][] = [
  ['overview', '数据概览'],
  ['bookings', '预约管理'],
  ['resources', '实验室 / 设备'],
  ['slots', '时间段'],
]

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const [tab, setTab] = useState<Tab>('overview')

  function logout() {
    clearToken()
    onLogout()
  }

  return (
    <div className="min-h-full">
      <header className="sticky top-0 z-20 border-b border-ink-200 bg-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-3">
          <div className="flex items-center gap-2.5">
            <span className="grid h-8 w-8 place-items-center rounded-full bg-ink-900 text-white">
              <MicIcon className="h-[18px] w-[18px]" />
            </span>
            <div>
              <div className="text-sm font-semibold tracking-tight text-ink-900">
                河北科技大学影视学院录音系 · 后台
              </div>
              <div className="text-[11px] text-ink-400">预约管理控制台</div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Link to="/" className="btn-ghost !py-2 text-[13px]">
              <HomeIcon className="h-4 w-4" /> 预约首页
            </Link>
            <button onClick={logout} className="btn-ghost !py-2 text-[13px]">
              <LogoutIcon className="h-4 w-4" /> 退出登录
            </button>
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-6xl px-5 py-6">
        <nav className="mb-6 inline-flex gap-1 rounded-lg border border-ink-200 bg-white p-1">
          {TABS.map(([key, label]) => (
            <button
              key={key}
              onClick={() => setTab(key)}
              className={`rounded-md px-4 py-1.5 text-[13px] font-medium tracking-tight transition ${
                tab === key
                  ? 'bg-ink-900 text-white'
                  : 'text-ink-500 hover:text-ink-800'
              }`}
            >
              {label}
            </button>
          ))}
        </nav>

        {tab === 'overview' && <OverviewTab />}
        {tab === 'bookings' && <BookingsTab />}
        {tab === 'resources' && <ResourcesTab />}
        {tab === 'slots' && <SlotsTab />}
      </div>
    </div>
  )
}

/* ------------------------- Overview ------------------------- */
function downloadExport() {
  const token = getToken()
  fetch('/api/admin/export', { headers: { Authorization: `Bearer ${token}` } })
    .then((r) => r.blob())
    .then((blob) => {
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `预约报表_${new Date().toISOString().slice(0, 10)}.xlsx`
      a.click()
      URL.revokeObjectURL(url)
    })
}

function OverviewTab() {
  const [bookings, setBookings] = useState<Booking[]>([])
  const [stats, setStats] = useState<Stats | null>(null)
  const [resources, setResources] = useState<Resource[]>([])
  const [slots, setSlots] = useState<Slot[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    Promise.all([
      api.get<Booking[]>('/admin/bookings'),
      api.get<Stats>('/admin/stats'),
      api.get<Resource[]>('/admin/resources'),
      api.get<Slot[]>('/admin/slots'),
    ])
      .then(([b, s, r, sl]) => {
        setBookings(b.data)
        setStats(s.data)
        setResources(r.data)
        setSlots(sl.data)
      })
      .finally(() => setLoading(false))
  }, [])

  const active = bookings.filter((b) => b.status !== 'cancelled')

  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const trend = Array.from({ length: 14 }, (_, i) => {
    const d = new Date(today)
    d.setDate(today.getDate() - (13 - i))
    const key = toDateStr(d)
    return {
      label: `${d.getMonth() + 1}/${d.getDate()}`,
      value: active.filter((b) => b.date === key).length,
    }
  })

  const byResource = resources
    .map((r) => ({
      label: r.name,
      value: active.filter((b) => b.resource_id === r.id).length,
    }))
    .sort((a, b) => b.value - a.value)

  const bySlot = slots.map((s) => ({
    label: s.name,
    value: active.filter((b) => b.slot_id === s.id).length,
  }))

  const statusSegments = [
    { label: '待核销', value: stats?.booked ?? 0, color: '#f59e0b' },
    { label: '已核销', value: stats?.verified ?? 0, color: '#10b981' },
    { label: '已取消', value: stats?.cancelled ?? 0, color: '#94a3b8' },
  ]

  if (loading) {
    return <div className="py-24 text-center text-sm text-ink-300">加载中…</div>
  }

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <p className="eyebrow">Overview</p>
          <h2 className="mt-1 text-[17px] font-semibold tracking-tight text-ink-900">数据概览</h2>
        </div>
        <button className="btn-primary" onClick={downloadExport}>
          <DownloadIcon className="h-4 w-4" /> 导出 Excel
        </button>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        <StatCard label="总预约" value={stats?.total ?? 0} tone="ink" />
        <StatCard label="待核销" value={stats?.booked ?? 0} tone="amber" />
        <StatCard label="已核销" value={stats?.verified ?? 0} tone="emerald" />
        <StatCard label="已取消" value={stats?.cancelled ?? 0} tone="slate" />
        <StatCard label="今日预约" value={stats?.today ?? 0} tone="accent" />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <ChartCard title="近 14 天预约趋势" subtitle="不含已取消">
          <VBarChart data={trend} />
        </ChartCard>
        <ChartCard title="状态占比" subtitle="全部预约">
          <Donut segments={statusSegments} />
        </ChartCard>
        <ChartCard title="各实验室 / 设备预约量" subtitle="不含已取消">
          <HBarChart data={byResource} />
        </ChartCard>
        <ChartCard title="各时段预约分布" subtitle="不含已取消">
          <HBarChart data={bySlot} />
        </ChartCard>
      </div>
    </div>
  )
}

function ChartCard({
  title,
  subtitle,
  children,
}: {
  title: string
  subtitle?: string
  children: React.ReactNode
}) {
  return (
    <div className="card p-4">
      <div className="mb-4 flex items-baseline justify-between">
        <h3 className="text-sm font-semibold tracking-tight text-ink-900">{title}</h3>
        {subtitle && <span className="text-[11px] text-ink-400">{subtitle}</span>}
      </div>
      {children}
    </div>
  )
}

function VBarChart({ data }: { data: { label: string; value: number }[] }) {
  const max = Math.max(1, ...data.map((d) => d.value))
  return (
    <div className="flex h-44 items-end gap-1.5">
      {data.map((d) => (
        <div key={d.label} className="flex h-full flex-1 flex-col items-center justify-end gap-1">
          <span className="text-[10px] tabular-nums text-ink-400">{d.value || ''}</span>
          <div
            className="w-full max-w-[18px] rounded-t bg-ink-900"
            style={{ height: `${Math.max(2, (d.value / max) * 100)}%` }}
          />
          <span className="text-[9px] tabular-nums text-ink-400">{d.label}</span>
        </div>
      ))}
    </div>
  )
}

function HBarChart({ data }: { data: { label: string; value: number }[] }) {
  const max = Math.max(1, ...data.map((d) => d.value))
  if (data.length === 0) {
    return <div className="py-8 text-center text-[13px] text-ink-300">暂无数据</div>
  }
  return (
    <div className="space-y-3">
      {data.map((d) => (
        <div key={d.label} className="flex items-center gap-3">
          <span className="w-28 shrink-0 truncate text-[12px] text-ink-600">{d.label}</span>
          <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-ink-100">
            <div
              className="h-full rounded-full bg-ink-900"
              style={{ width: `${(d.value / max) * 100}%` }}
            />
          </div>
          <span className="w-7 shrink-0 text-right text-[12px] tabular-nums text-ink-500">
            {d.value}
          </span>
        </div>
      ))}
    </div>
  )
}

function Donut({ segments }: { segments: { label: string; value: number; color: string }[] }) {
  const total = segments.reduce((s, x) => s + x.value, 0)
  const r = 42
  const c = 2 * Math.PI * r
  let acc = 0
  return (
    <div className="flex items-center gap-5">
      <div className="relative h-32 w-32 shrink-0">
        <svg viewBox="0 0 100 100" className="h-full w-full -rotate-90">
          <circle cx="50" cy="50" r={r} fill="none" stroke="#f1f1f2" strokeWidth="13" />
          {total > 0 &&
            segments.map((s) => {
              const frac = s.value / total
              const dash = `${frac * c} ${c}`
              const offset = -acc * c
              acc += frac
              return (
                <circle
                  key={s.label}
                  cx="50"
                  cy="50"
                  r={r}
                  fill="none"
                  stroke={s.color}
                  strokeWidth="13"
                  strokeDasharray={dash}
                  strokeDashoffset={offset}
                />
              )
            })}
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-xl font-semibold tabular-nums text-ink-900">{total}</span>
          <span className="text-[10px] text-ink-400">总计</span>
        </div>
      </div>
      <div className="space-y-2">
        {segments.map((s) => (
          <div key={s.label} className="flex items-center gap-2 text-[13px]">
            <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: s.color }} />
            <span className="text-ink-600">{s.label}</span>
            <span className="tabular-nums font-medium text-ink-900">{s.value}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

/* ------------------------- Bookings ------------------------- */
function BookingsTab() {
  const [bookings, setBookings] = useState<Booking[]>([])
  const [resources, setResources] = useState<Resource[]>([])
  const [stats, setStats] = useState<Stats | null>(null)
  const [status, setStatus] = useState('')
  const [resourceId, setResourceId] = useState('')
  const [date, setDate] = useState('')
  const [keyword, setKeyword] = useState('')
  const [loading, setLoading] = useState(false)

  function load() {
    setLoading(true)
    const params: Record<string, string> = {}
    if (status) params.status = status
    if (resourceId) params.resource_id = resourceId
    if (date) params.date = date
    if (keyword) params.keyword = keyword
    Promise.all([
      api.get<Booking[]>('/admin/bookings', { params }),
      api.get<Stats>('/admin/stats'),
    ])
      .then(([b, s]) => {
        setBookings(b.data)
        setStats(s.data)
      })
      .finally(() => setLoading(false))
  }

  useEffect(() => {
    api.get<Resource[]>('/admin/resources').then((r) => setResources(r.data))
  }, [])
  useEffect(load, [status, resourceId, date, keyword])

  async function verify(id: number) {
    await api.post(`/admin/bookings/${id}/verify`)
    load()
  }
  async function cancel(id: number) {
    if (!confirm('确认取消该预约？')) return
    await api.post(`/admin/bookings/${id}/cancel`)
    load()
  }

  function exportXlsx() {
    const params = new URLSearchParams()
    if (status) params.set('status', status)
    if (resourceId) params.set('resource_id', resourceId)
    if (date) params.set('date', date)
    if (keyword) params.set('keyword', keyword)
    const token = getToken()
    fetch(`/api/admin/export?${params.toString()}`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then((r) => r.blob())
      .then((blob) => {
        const url = URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = `预约报表_${new Date().toISOString().slice(0, 10)}.xlsx`
        a.click()
        URL.revokeObjectURL(url)
      })
  }

  const hasFilter = !!(status || resourceId || date || keyword)

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        <StatCard label="总预约" value={stats?.total ?? 0} tone="ink" />
        <StatCard label="待核销" value={stats?.booked ?? 0} tone="amber" />
        <StatCard label="已核销" value={stats?.verified ?? 0} tone="emerald" />
        <StatCard label="已取消" value={stats?.cancelled ?? 0} tone="slate" />
        <StatCard label="今日预约" value={stats?.today ?? 0} tone="accent" />
      </div>

      <div className="card p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div>
            <span className="label">状态</span>
            <select
              className="input !w-32"
              value={status}
              onChange={(e) => setStatus(e.target.value)}
            >
              <option value="">全部</option>
              <option value="booked">待核销</option>
              <option value="verified">已核销</option>
              <option value="cancelled">已取消</option>
            </select>
          </div>
          <div>
            <span className="label">资源</span>
            <select
              className="input !w-40"
              value={resourceId}
              onChange={(e) => setResourceId(e.target.value)}
            >
              <option value="">全部</option>
              {resources.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <span className="label">日期</span>
            <input
              type="date"
              className="input !w-40"
              value={date}
              onChange={(e) => setDate(e.target.value)}
            />
          </div>
          <div className="min-w-[180px] flex-1">
            <span className="label">搜索</span>
            <div className="relative">
              <SearchIcon className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-300" />
              <input
                className="input pl-9"
                placeholder="姓名 / 电话 / 指导教师"
                value={keyword}
                onChange={(e) => setKeyword(e.target.value)}
              />
            </div>
          </div>
          <button
            className="btn-ghost"
            disabled={!hasFilter}
            onClick={() => {
              setStatus('')
              setResourceId('')
              setDate('')
              setKeyword('')
            }}
          >
            重置
          </button>
          <button className="btn-primary" onClick={exportXlsx}>
            <DownloadIcon className="h-4 w-4" /> 导出 Excel
          </button>
        </div>
      </div>

      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[900px] text-sm">
            <thead>
              <tr className="border-b border-ink-100 bg-ink-50/60 text-left text-[11px] uppercase tracking-wider text-ink-400">
                <th className="px-4 py-3 font-medium">预约人</th>
                <th className="px-4 py-3 font-medium">资源</th>
                <th className="px-4 py-3 font-medium">日期 / 时段</th>
                <th className="px-4 py-3 font-medium">人数 / 数量</th>
                <th className="px-4 py-3 font-medium">指导教师</th>
                <th className="px-4 py-3 font-medium">状态</th>
                <th className="px-4 py-3 text-right font-medium">操作</th>
              </tr>
            </thead>
            <tbody>
              {bookings.map((b) => {
                const meta = STATUS_META[b.status]
                return (
                  <tr
                    key={b.id}
                    className="border-b border-ink-100/70 last:border-0 transition hover:bg-ink-50/50"
                  >
                    <td className="px-4 py-3">
                      <div className="font-medium text-ink-900">{b.applicant_name}</div>
                      <div className="text-xs text-ink-400">{b.phone}</div>
                      {b.major && <div className="text-xs text-ink-400">{b.major}</div>}
                    </td>
                    <td className="px-4 py-3 text-ink-600">{b.resource.name}</td>
                    <td className="px-4 py-3 text-ink-600">
                      <div>{b.date}</div>
                      <div className="text-xs text-ink-400">
                        {b.slot.name} {b.slot.start_time}-{b.slot.end_time}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-ink-600 tabular-nums">
                      {b.num_people} 人 / {b.quantity} 套
                    </td>
                    <td className="px-4 py-3 text-ink-600">{b.instructor || '—'}</td>
                    <td className="px-4 py-3">
                      <span className={`badge ${meta.className}`}>
                        <span className={`h-1.5 w-1.5 rounded-full ${meta.dot}`} />
                        {meta.label}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex justify-end gap-2">
                        {b.status === 'booked' && (
                          <>
                            <button
                              className="rounded-lg bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-700 ring-1 ring-inset ring-emerald-100 transition hover:bg-emerald-100"
                              onClick={() => verify(b.id)}
                            >
                              核销
                            </button>
                            <button
                              className="rounded-lg bg-white px-3 py-1.5 text-xs font-medium text-rose-600 ring-1 ring-inset ring-rose-200 transition hover:bg-rose-50"
                              onClick={() => cancel(b.id)}
                            >
                              取消
                            </button>
                          </>
                        )}
                        {b.status === 'verified' && b.verified_at && (
                          <span className="text-xs text-ink-400">
                            {formatDateTime(b.verified_at)} 核销
                          </span>
                        )}
                        {b.status === 'cancelled' && <span className="text-xs text-ink-300">—</span>}
                      </div>
                    </td>
                  </tr>
                )
              })}
              {bookings.length === 0 && !loading && (
                <tr>
                  <td colSpan={7} className="px-4 py-20 text-center text-sm text-ink-300">
                    暂无预约记录
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}

function StatCard({
  label,
  value,
  tone,
}: {
  label: string
  value: number
  tone: 'ink' | 'amber' | 'emerald' | 'slate' | 'accent'
}) {
  const dot = {
    ink: 'bg-ink-900',
    amber: 'bg-amber-400',
    emerald: 'bg-emerald-500',
    slate: 'bg-ink-300',
    accent: 'bg-accent-500',
  }
  return (
    <div className="card px-4 py-3.5">
      <div className="flex items-center gap-1.5 text-[13px] text-ink-500">
        <span className={`h-1.5 w-1.5 rounded-full ${dot[tone]}`} />
        {label}
      </div>
      <div className="mt-1.5 text-[28px] font-semibold leading-none tracking-tight text-ink-900 tabular-nums">
        {value}
      </div>
    </div>
  )
}

/* ------------------------- Resources ------------------------- */
const EMPTY_RESOURCE: Omit<Resource, 'id'> = {
  name: '',
  kind: 'lab',
  description: '',
  image_url: '',
  total_quantity: 1,
  individual_bookable: true,
  sort_order: 0,
  is_active: true,
}

function ResourcesTab() {
  const [resources, setResources] = useState<Resource[]>([])
  const [editing, setEditing] = useState<Partial<Resource> | null>(null)
  const [uploadingImage, setUploadingImage] = useState(false)

  function load() {
    api.get<Resource[]>('/admin/resources').then((r) => setResources(r.data))
  }
  useEffect(load, [])

  async function save() {
    if (!editing) return
    if (editing.id) {
      await api.put(`/admin/resources/${editing.id}`, editing)
    } else {
      await api.post('/admin/resources', editing)
    }
    setEditing(null)
    load()
  }
  async function handleImageUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.currentTarget.files?.[0]
    if (!file) return
    setUploadingImage(true)
    try {
      const url = await uploadImage(file)
      setEditing((current) => (current ? { ...current, image_url: url } : current))
    } catch {
      alert('图片上传失败，请确认文件小于 5MB 且为 PNG、JPG、WebP 或 GIF。')
    } finally {
      setUploadingImage(false)
      e.currentTarget.value = ''
    }
  }
  async function remove(id: number) {
    if (!confirm('删除该资源？相关预约也会被移除。')) return
    await api.delete(`/admin/resources/${id}`)
    load()
  }

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <div>
          <p className="eyebrow">Resources</p>
          <h2 className="mt-1 text-[17px] font-semibold tracking-tight text-ink-900">
            实验室 / 设备管理
          </h2>
        </div>
        <button className="btn-primary" onClick={() => setEditing({ ...EMPTY_RESOURCE })}>
          <PlusIcon className="h-4 w-4" /> 新增资源
        </button>
      </div>

      <div className="grid gap-3 xl:grid-cols-2">
        {resources.map((r) => (
          <div key={r.id} className="card p-3">
            <div className="flex gap-3">
              <div className="h-14 w-14 shrink-0 overflow-hidden rounded-2xl bg-ink-100 ring-1 ring-inset ring-ink-200/70">
                {r.image_url ? (
                  <img src={r.image_url} alt={r.name} className="h-full w-full object-cover" />
                ) : (
                  <div className="grid h-full place-items-center bg-ink-100 text-ink-300">
                    <ImageIcon className="h-7 w-7" />
                  </div>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="truncate font-semibold tracking-tight text-ink-900">{r.name}</div>
                    <div className="mt-0.5 text-[11px] text-ink-400">
                      {r.kind === 'lab' ? '实验室' : '设备'} · 每时段 {r.total_quantity} 名额
                    </div>
                  </div>
                  {!r.is_active && (
                    <span className="badge shrink-0 bg-ink-100 text-ink-400">已停用</span>
                  )}
                </div>
                <p className="mt-2 line-clamp-2 text-[13px] leading-relaxed text-ink-500">
                  {r.description || '暂无描述'}
                </p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {!r.individual_bookable && (
                    <span className="badge bg-amber-50 text-amber-700">个人不可预约</span>
                  )}
                  <span className="badge bg-ink-50 text-ink-500">排序 {r.sort_order}</span>
                </div>
              </div>
            </div>
            <div className="mt-2.5 flex gap-2 border-t border-ink-100 pt-2.5">
              <button className="btn-ghost flex-1 !py-2 text-[13px]" onClick={() => setEditing(r)}>
                编辑
              </button>
              <button className="btn-danger !py-2 text-[13px]" onClick={() => remove(r.id)}>
                删除
              </button>
            </div>
          </div>
        ))}
      </div>

      {editing && (
        <Modal
          title={editing.id ? '编辑资源' : '新增资源'}
          onClose={() => setEditing(null)}
          onSave={save}
        >
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <label className="block sm:col-span-2">
              <span className="label">名称</span>
              <input
                className="input"
                value={editing.name ?? ''}
                onChange={(e) => setEditing({ ...editing, name: e.target.value })}
              />
            </label>
            <label className="block">
              <span className="label">类型</span>
              <select
                className="input"
                value={editing.kind ?? 'lab'}
                onChange={(e) => setEditing({ ...editing, kind: e.target.value as Resource['kind'] })}
              >
                <option value="lab">实验室</option>
                <option value="equipment">设备</option>
              </select>
            </label>
            <label className="block">
              <span className="label">每时段名额</span>
              <input
                type="number"
                min={1}
                className="input"
                value={editing.total_quantity ?? 1}
                onChange={(e) =>
                  setEditing({ ...editing, total_quantity: Number(e.target.value) || 1 })
                }
              />
            </label>
            <label className="block sm:col-span-2">
              <span className="label">描述</span>
              <textarea
                className="input min-h-[72px] resize-none"
                value={editing.description ?? ''}
                onChange={(e) => setEditing({ ...editing, description: e.target.value })}
              />
            </label>
            <div className="sm:col-span-2">
              <span className="label">资源图片</span>
              <div className="rounded-lg border border-ink-200 bg-ink-50 p-3">
                <div className="grid gap-3 sm:grid-cols-[132px_1fr]">
                  <div className="h-20 overflow-hidden rounded-xl bg-white ring-1 ring-inset ring-ink-200">
                    {editing.image_url ? (
                      <img
                        src={editing.image_url}
                        alt="资源预览"
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <div className="grid h-full place-items-center text-ink-300">
                        <ImageIcon className="h-8 w-8" />
                      </div>
                    )}
                  </div>
                  <div className="flex flex-col justify-center">
                    <p className="text-[13px] leading-relaxed text-ink-500">
                      上传后自动填入地址，并同步到前台卡片。
                    </p>
                    <div className="mt-3 flex flex-wrap gap-2">
                      <label className="btn-ghost cursor-pointer !py-2 text-[13px]">
                        <UploadIcon className="h-4 w-4" />
                        {uploadingImage ? '上传中…' : '上传图片'}
                        <input
                          type="file"
                          accept="image/png,image/jpeg,image/webp,image/gif"
                          className="hidden"
                          disabled={uploadingImage}
                          onChange={handleImageUpload}
                        />
                      </label>
                      {editing.image_url && (
                        <button
                          type="button"
                          className="btn-danger !py-2 text-[13px]"
                          onClick={() => setEditing({ ...editing, image_url: '' })}
                        >
                          移除
                        </button>
                      )}
                    </div>
                  </div>
                </div>
                <input
                  className="input mt-3"
                  placeholder="/uploads/images/… 或 https://…"
                  value={editing.image_url ?? ''}
                  onChange={(e) => setEditing({ ...editing, image_url: e.target.value })}
                />
              </div>
            </div>
            <label className="block">
              <span className="label">排序</span>
              <input
                type="number"
                className="input"
                value={editing.sort_order ?? 0}
                onChange={(e) => setEditing({ ...editing, sort_order: Number(e.target.value) || 0 })}
              />
            </label>
            <div className="flex flex-col gap-3 pt-7">
              <label className="flex items-center gap-2 text-[13px] text-ink-600">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-ink-300 text-ink-900 focus:ring-ink-900/20"
                  checked={editing.individual_bookable ?? true}
                  onChange={(e) => setEditing({ ...editing, individual_bookable: e.target.checked })}
                />
                允许个人预约
              </label>
              <label className="flex items-center gap-2 text-[13px] text-ink-600">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-ink-300 text-ink-900 focus:ring-ink-900/20"
                  checked={editing.is_active ?? true}
                  onChange={(e) => setEditing({ ...editing, is_active: e.target.checked })}
                />
                启用（前台可见）
              </label>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}

/* ------------------------- Slots ------------------------- */
const EMPTY_SLOT: Omit<Slot, 'id'> = {
  name: '',
  start_time: '08:00',
  end_time: '12:00',
  sort_order: 0,
  is_active: true,
}

function SlotsTab() {
  const [slots, setSlots] = useState<Slot[]>([])
  const [editing, setEditing] = useState<Partial<Slot> | null>(null)

  function load() {
    api.get<Slot[]>('/admin/slots').then((r) => setSlots(r.data))
  }
  useEffect(load, [])

  async function save() {
    if (!editing) return
    if (editing.id) {
      await api.put(`/admin/slots/${editing.id}`, editing)
    } else {
      await api.post('/admin/slots', editing)
    }
    setEditing(null)
    load()
  }
  async function remove(id: number) {
    if (!confirm('删除该时间段？')) return
    await api.delete(`/admin/slots/${id}`)
    load()
  }

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <div>
          <p className="eyebrow">Time Slots</p>
          <h2 className="mt-1 text-[17px] font-semibold tracking-tight text-ink-900">时间段管理</h2>
        </div>
        <button className="btn-primary" onClick={() => setEditing({ ...EMPTY_SLOT })}>
          <PlusIcon className="h-4 w-4" /> 新增时间段
        </button>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {slots.map((s) => (
          <div key={s.id} className="card p-5">
            <div className="flex items-center justify-between">
              <div className="text-[15px] font-semibold tracking-tight text-ink-900">{s.name}</div>
              {!s.is_active && <span className="badge bg-ink-100 text-ink-400">已停用</span>}
            </div>
            <div className="mt-2 text-2xl font-semibold tracking-tight text-ink-900 tabular-nums">
              {s.start_time}
              <span className="mx-1.5 text-ink-300">–</span>
              {s.end_time}
            </div>
            <div className="mt-4 flex gap-2">
              <button className="btn-ghost flex-1 !py-2 text-[13px]" onClick={() => setEditing(s)}>
                编辑
              </button>
              <button className="btn-danger !py-2 text-[13px]" onClick={() => remove(s.id)}>
                删除
              </button>
            </div>
          </div>
        ))}
      </div>

      {editing && (
        <Modal
          title={editing.id ? '编辑时间段' : '新增时间段'}
          onClose={() => setEditing(null)}
          onSave={save}
        >
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <label className="block sm:col-span-2">
              <span className="label">名称</span>
              <input
                className="input"
                placeholder="如 上午"
                value={editing.name ?? ''}
                onChange={(e) => setEditing({ ...editing, name: e.target.value })}
              />
            </label>
            <label className="block">
              <span className="label">开始时间</span>
              <input
                type="time"
                className="input"
                value={editing.start_time ?? '08:00'}
                onChange={(e) => setEditing({ ...editing, start_time: e.target.value })}
              />
            </label>
            <label className="block">
              <span className="label">结束时间</span>
              <input
                type="time"
                className="input"
                value={editing.end_time ?? '12:00'}
                onChange={(e) => setEditing({ ...editing, end_time: e.target.value })}
              />
            </label>
            <label className="block">
              <span className="label">排序</span>
              <input
                type="number"
                className="input"
                value={editing.sort_order ?? 0}
                onChange={(e) => setEditing({ ...editing, sort_order: Number(e.target.value) || 0 })}
              />
            </label>
            <label className="flex items-center gap-2 pt-7 text-[13px] text-ink-600">
              <input
                type="checkbox"
                className="h-4 w-4 rounded border-ink-300 text-ink-900 focus:ring-ink-900/20"
                checked={editing.is_active ?? true}
                onChange={(e) => setEditing({ ...editing, is_active: e.target.checked })}
              />
              启用
            </label>
          </div>
        </Modal>
      )}
    </div>
  )
}

/* ------------------------- Shared Modal ------------------------- */
function Modal({
  title,
  children,
  onClose,
  onSave,
}: {
  title: string
  children: React.ReactNode
  onClose: () => void
  onSave: () => void
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink-950/45 p-0 backdrop-blur-sm animate-fade-in sm:items-center sm:p-4">
      <div className="max-h-[92vh] w-full max-w-xl animate-fade-up overflow-y-auto rounded-t-2xl bg-white p-4 shadow-pop sm:rounded-xl sm:p-5">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-semibold tracking-tight text-ink-900">{title}</h3>
          <button
            onClick={onClose}
            className="grid h-9 w-9 place-items-center rounded-full text-ink-400 transition hover:bg-ink-100 hover:text-ink-700"
          >
            <CloseIcon className="h-4 w-4" />
          </button>
        </div>
        <div className="mt-6">{children}</div>
        <div className="mt-6 flex gap-3">
          <button className="btn-ghost flex-1" onClick={onClose}>
            取消
          </button>
          <button className="btn-primary flex-1" onClick={onSave}>
            保存
          </button>
        </div>
      </div>
    </div>
  )
}
