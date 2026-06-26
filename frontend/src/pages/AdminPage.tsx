import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  api,
  clearToken,
  getToken,
  setToken,
  type Booking,
  type Resource,
  type Slot,
  type Stats,
} from '../api'
import { formatDateTime, STATUS_META } from '../lib'

type Tab = 'bookings' | 'resources' | 'slots'

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
    <div className="grid min-h-full place-items-center bg-gradient-to-br from-brand-700 via-brand-600 to-brand-500 p-4">
      <form
        onSubmit={submit}
        className="w-full max-w-sm animate-fade-up rounded-3xl bg-white p-8 shadow-2xl"
      >
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-brand-50 text-2xl">
          🎙️
        </div>
        <h1 className="mt-4 text-center text-xl font-bold text-slate-800">预约系统后台</h1>
        <p className="mt-1 text-center text-sm text-slate-400">录音实验室管理控制台</p>

        <div className="mt-6 space-y-4">
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
          <div className="mt-4 rounded-xl bg-rose-50 px-3.5 py-2.5 text-sm text-rose-600">
            {error}
          </div>
        )}

        <button className="btn-primary mt-6 w-full" disabled={loading}>
          {loading ? '登录中…' : '登录'}
        </button>
        <Link
          to="/"
          className="mt-4 block text-center text-sm text-slate-400 hover:text-brand-500"
        >
          ← 返回预约首页
        </Link>
      </form>
    </div>
  )
}

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const [tab, setTab] = useState<Tab>('bookings')

  function logout() {
    clearToken()
    onLogout()
  }

  return (
    <div className="min-h-full">
      <header className="sticky top-0 z-20 border-b border-slate-200 bg-white/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
          <div className="flex items-center gap-2.5">
            <span className="grid h-9 w-9 place-items-center rounded-xl bg-brand-50 text-lg">
              🎙️
            </span>
            <div>
              <div className="text-sm font-bold text-slate-800">录音实验室 · 后台</div>
              <div className="text-xs text-slate-400">预约管理控制台</div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Link to="/" className="btn-ghost !py-2 text-sm">
              预约首页
            </Link>
            <button onClick={logout} className="btn-ghost !py-2 text-sm">
              退出登录
            </button>
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-6xl px-4 py-6">
        <nav className="mb-6 flex gap-2">
          {(
            [
              ['bookings', '预约管理'],
              ['resources', '实验室 / 设备'],
              ['slots', '时间段'],
            ] as [Tab, string][]
          ).map(([key, label]) => (
            <button
              key={key}
              onClick={() => setTab(key)}
              className={`rounded-xl px-4 py-2 text-sm font-semibold transition ${
                tab === key
                  ? 'bg-brand-500 text-white shadow-soft'
                  : 'bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50'
              }`}
            >
              {label}
            </button>
          ))}
        </nav>

        {tab === 'bookings' && <BookingsTab />}
        {tab === 'resources' && <ResourcesTab />}
        {tab === 'slots' && <SlotsTab />}
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

  return (
    <div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        <StatCard label="总预约" value={stats?.total ?? 0} tone="brand" />
        <StatCard label="待核销" value={stats?.booked ?? 0} tone="amber" />
        <StatCard label="已核销" value={stats?.verified ?? 0} tone="emerald" />
        <StatCard label="已取消" value={stats?.cancelled ?? 0} tone="slate" />
        <StatCard label="今日预约" value={stats?.today ?? 0} tone="brand" />
      </div>

      <div className="card mt-5 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div>
            <span className="label">状态</span>
            <select className="input !w-32" value={status} onChange={(e) => setStatus(e.target.value)}>
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
          <div className="flex-1">
            <span className="label">搜索</span>
            <input
              className="input"
              placeholder="姓名 / 电话 / 指导教师"
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
            />
          </div>
          <button className="btn-ghost" onClick={() => { setStatus(''); setResourceId(''); setDate(''); setKeyword('') }}>
            重置
          </button>
          <button className="btn-primary" onClick={exportXlsx}>
            ⬇ 导出 Excel
          </button>
        </div>
      </div>

      <div className="card mt-5 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[900px] text-sm">
            <thead>
              <tr className="border-b border-slate-100 bg-slate-50/70 text-left text-xs uppercase tracking-wide text-slate-400">
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
                  <tr key={b.id} className="border-b border-slate-50 last:border-0 hover:bg-slate-50/50">
                    <td className="px-4 py-3">
                      <div className="font-semibold text-slate-800">{b.applicant_name}</div>
                      <div className="text-xs text-slate-400">{b.phone}</div>
                      {b.major && <div className="text-xs text-slate-400">{b.major}</div>}
                    </td>
                    <td className="px-4 py-3 text-slate-600">{b.resource.name}</td>
                    <td className="px-4 py-3 text-slate-600">
                      <div>{b.date}</div>
                      <div className="text-xs text-slate-400">
                        {b.slot.name} {b.slot.start_time}-{b.slot.end_time}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-slate-600">
                      {b.num_people} 人 / {b.quantity} 套
                    </td>
                    <td className="px-4 py-3 text-slate-600">{b.instructor || '—'}</td>
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
                              className="rounded-lg bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-600 hover:bg-emerald-100"
                              onClick={() => verify(b.id)}
                            >
                              核销
                            </button>
                            <button
                              className="rounded-lg bg-rose-50 px-3 py-1.5 text-xs font-semibold text-rose-500 hover:bg-rose-100"
                              onClick={() => cancel(b.id)}
                            >
                              取消
                            </button>
                          </>
                        )}
                        {b.status === 'verified' && b.verified_at && (
                          <span className="text-xs text-slate-400">
                            {formatDateTime(b.verified_at)} 核销
                          </span>
                        )}
                        {b.status === 'cancelled' && <span className="text-xs text-slate-300">—</span>}
                      </div>
                    </td>
                  </tr>
                )
              })}
              {bookings.length === 0 && !loading && (
                <tr>
                  <td colSpan={7} className="px-4 py-16 text-center text-slate-300">
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
  tone: 'brand' | 'amber' | 'emerald' | 'slate'
}) {
  const tones = {
    brand: 'from-brand-500 to-brand-600',
    amber: 'from-amber-400 to-amber-500',
    emerald: 'from-emerald-400 to-emerald-500',
    slate: 'from-slate-400 to-slate-500',
  }
  return (
    <div className={`rounded-2xl bg-gradient-to-br ${tones[tone]} p-4 text-white shadow-soft`}>
      <div className="text-3xl font-bold">{value}</div>
      <div className="mt-1 text-sm text-white/85">{label}</div>
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
  async function remove(id: number) {
    if (!confirm('删除该资源？相关预约也会被移除。')) return
    await api.delete(`/admin/resources/${id}`)
    load()
  }

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-lg font-bold text-slate-800">实验室 / 设备管理</h2>
        <button className="btn-primary" onClick={() => setEditing({ ...EMPTY_RESOURCE })}>
          + 新增资源
        </button>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {resources.map((r) => (
          <div key={r.id} className="card p-4">
            <div className="flex items-start justify-between">
              <div className="flex items-center gap-3">
                <span className="grid h-11 w-11 place-items-center rounded-xl bg-brand-50 text-xl">
                  {r.kind === 'lab' ? '🎙️' : '🎛️'}
                </span>
                <div>
                  <div className="font-bold text-slate-800">{r.name}</div>
                  <div className="text-xs text-slate-400">
                    {r.kind === 'lab' ? '实验室' : '设备'} · 名额 {r.total_quantity}
                  </div>
                </div>
              </div>
              {!r.is_active && (
                <span className="badge bg-slate-100 text-slate-400">已停用</span>
              )}
            </div>
            <p className="mt-3 line-clamp-2 min-h-[2.5rem] text-sm text-slate-500">
              {r.description || '暂无描述'}
            </p>
            <div className="mt-3 flex flex-wrap gap-2 text-xs">
              {!r.individual_bookable && (
                <span className="badge bg-amber-50 text-amber-600">个人不可预约</span>
              )}
              <span className="badge bg-slate-50 text-slate-500">排序 {r.sort_order}</span>
            </div>
            <div className="mt-4 flex gap-2">
              <button className="btn-ghost flex-1 !py-2 text-sm" onClick={() => setEditing(r)}>
                编辑
              </button>
              <button className="btn-danger !py-2 text-sm" onClick={() => remove(r.id)}>
                删除
              </button>
            </div>
          </div>
        ))}
      </div>

      {editing && (
        <Modal title={editing.id ? '编辑资源' : '新增资源'} onClose={() => setEditing(null)} onSave={save}>
          <div className="grid grid-cols-2 gap-4">
            <label className="col-span-2 block">
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
            <label className="col-span-2 block">
              <span className="label">描述</span>
              <textarea
                className="input min-h-[72px] resize-none"
                value={editing.description ?? ''}
                onChange={(e) => setEditing({ ...editing, description: e.target.value })}
              />
            </label>
            <label className="col-span-2 block">
              <span className="label">图片地址（可选）</span>
              <input
                className="input"
                placeholder="https://…"
                value={editing.image_url ?? ''}
                onChange={(e) => setEditing({ ...editing, image_url: e.target.value })}
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
            <div className="flex flex-col gap-3 pt-7">
              <label className="flex items-center gap-2 text-sm text-slate-600">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-slate-300"
                  checked={editing.individual_bookable ?? true}
                  onChange={(e) => setEditing({ ...editing, individual_bookable: e.target.checked })}
                />
                允许个人预约
              </label>
              <label className="flex items-center gap-2 text-sm text-slate-600">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-slate-300"
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
        <h2 className="text-lg font-bold text-slate-800">时间段管理</h2>
        <button className="btn-primary" onClick={() => setEditing({ ...EMPTY_SLOT })}>
          + 新增时间段
        </button>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {slots.map((s) => (
          <div key={s.id} className="card p-5">
            <div className="flex items-center justify-between">
              <div className="text-lg font-bold text-slate-800">{s.name}</div>
              {!s.is_active && <span className="badge bg-slate-100 text-slate-400">已停用</span>}
            </div>
            <div className="mt-2 text-2xl font-bold text-brand-500">
              {s.start_time}
              <span className="mx-1 text-slate-300">–</span>
              {s.end_time}
            </div>
            <div className="mt-4 flex gap-2">
              <button className="btn-ghost flex-1 !py-2 text-sm" onClick={() => setEditing(s)}>
                编辑
              </button>
              <button className="btn-danger !py-2 text-sm" onClick={() => remove(s.id)}>
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
          <div className="grid grid-cols-2 gap-4">
            <label className="col-span-2 block">
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
            <label className="flex items-center gap-2 pt-7 text-sm text-slate-600">
              <input
                type="checkbox"
                className="h-4 w-4 rounded border-slate-300"
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
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-slate-900/40 p-0 backdrop-blur-sm sm:items-center sm:p-4">
      <div className="max-h-[92vh] w-full max-w-lg animate-fade-up overflow-y-auto rounded-t-3xl bg-white p-6 shadow-2xl sm:rounded-3xl">
        <div className="flex items-center justify-between">
          <h3 className="text-xl font-bold text-slate-800">{title}</h3>
          <button
            onClick={onClose}
            className="grid h-9 w-9 place-items-center rounded-full text-slate-400 hover:bg-slate-100"
          >
            ✕
          </button>
        </div>
        <div className="mt-5">{children}</div>
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
