import { getToken, logout } from './keycloak'

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message)
  }
}

async function apiFetch(path: string, options: RequestInit = {}): Promise<Response> {
  let token: string
  try {
    token = await getToken()
  } catch {
    logout()
    throw new ApiError(401, 'Session expired')
  }

  const res = await fetch(path, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...options.headers,
    },
  })

  if (res.status === 401) {
    logout()
    throw new ApiError(401, 'Unauthorised')
  }

  if (!res.ok) {
    let message = `HTTP ${res.status}`
    try {
      const body = await res.text()
      if (body) message = body
    } catch {
      // ignore
    }
    throw new ApiError(res.status, message)
  }

  return res
}

export async function apiGet<T>(path: string): Promise<T> {
  const res = await apiFetch(path)
  if (res.status === 204) return undefined as T
  return res.json()
}

export async function apiPost<T>(path: string, body?: unknown): Promise<T> {
  const res = await apiFetch(path, {
    method: 'POST',
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  if (res.status === 204) return undefined as T
  return res.json()
}

export async function apiPatch<T>(path: string, body?: unknown): Promise<T> {
  const res = await apiFetch(path, {
    method: 'PATCH',
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  if (res.status === 204) return undefined as T
  return res.json()
}

export async function apiPut<T>(path: string, body?: unknown): Promise<T> {
  const res = await apiFetch(path, {
    method: 'PUT',
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  if (res.status === 204) return undefined as T
  return res.json()
}

export async function apiDelete(path: string): Promise<void> {
  await apiFetch(path, { method: 'DELETE' })
}
