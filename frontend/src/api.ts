import axios from 'axios'

export const api = axios.create({ baseURL: '/api' })

const TOKEN_KEY = 'ys_admin_token'

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}
export function setToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token)
}
export function clearToken() {
  localStorage.removeItem(TOKEN_KEY)
}

api.interceptors.request.use((config) => {
  const token = getToken()
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

// ---------- Types ----------
export interface Resource {
  id: number
  name: string
  kind: 'lab' | 'equipment'
  description: string
  image_url: string
  total_quantity: number
  individual_bookable: boolean
  sort_order: number
  is_active: boolean
}

export interface Slot {
  id: number
  name: string
  start_time: string
  end_time: string
  sort_order: number
  is_active: boolean
}

export interface SlotAvailability {
  slot: Slot
  total_quantity: number
  booked_quantity: number
  available: number
}

export interface ResourceAvailability {
  resource: Resource
  date: string
  slots: SlotAvailability[]
}

export interface Booking {
  id: number
  resource_id: number
  slot_id: number
  date: string
  applicant_name: string
  phone: string
  major: string
  num_people: number
  instructor: string
  description: string
  quantity: number
  status: 'booked' | 'verified' | 'cancelled'
  created_at: string
  verified_at: string | null
  resource: Resource
  slot: Slot
}

export interface Stats {
  total: number
  booked: number
  verified: number
  cancelled: number
  today: number
}

export interface BookingForm {
  resource_id: number
  slot_id: number
  date: string
  applicant_name: string
  phone: string
  major: string
  num_people: number
  instructor: string
  description: string
  quantity: number
}

export interface ImageUploadResponse {
  url: string
}

export async function uploadImage(file: File): Promise<string> {
  const form = new FormData()
  form.append('image', file)
  const res = await api.post<ImageUploadResponse>('/admin/uploads/images', form)
  return res.data.url
}
