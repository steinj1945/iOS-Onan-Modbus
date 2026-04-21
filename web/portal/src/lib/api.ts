const BASE = '/api'

function authHeaders(): HeadersInit {
  const token = localStorage.getItem('token')
  return token ? { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' } : { 'Content-Type': 'application/json' }
}

async function req<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: authHeaders(),
    body: body ? JSON.stringify(body) : undefined
  })
  if (!res.ok) throw new Error(await res.text())
  if (res.status === 204) return undefined as T
  return res.json()
}

export const api = {
  login:      (username: string, password: string) =>
                req<{ token: string }>('POST', '/auth/login', { username, password }),
  listKeys:   () => req<PassKeyRow[]>('GET', '/keys'),
  createKey:  (label: string) => req<NewKeyResult>('POST', '/keys', { label }),
  revokeKey:  (id: number) => req<void>('DELETE', `/keys/${id}`),
  listLogs:   (page = 1) => req<LogPage>('GET', `/logs?page=${page}&pageSize=50`),
}

export interface PassKeyRow {
  id: number
  label: string
  isActive: boolean
  createdAt: string
  revokedAt: string | null
  secretHint: string
}

export interface NewKeyResult {
  id: number
  label: string
  secretHint: string
  secret: string   // plain hex — shown once, used for QR
}

export interface LogEntry {
  id: number
  event: string
  occurredAt: string
  deviceLabel: string | null
  keyLabel: string | null
}

export interface LogPage {
  total: number
  page: number
  pageSize: number
  items: LogEntry[]
}
