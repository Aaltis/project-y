import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { apiGet, apiPost, ApiError } from '../../api'
import DataTable from '../../components/DataTable'
import ErrorBanner from '../../components/ErrorBanner'

interface Account {
  id: string
  name: string
  ownerId: string
  createdAt: string
}

export default function AccountsList() {
  const navigate = useNavigate()
  const [accounts, setAccounts] = useState<Account[]>([])
  const [error, setError] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [name, setName] = useState('')
  const [loading, setLoading] = useState(true)

  async function load() {
    try {
      const data = await apiGet<Account[]>('/api/accounts')
      setAccounts(data)
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Failed to load accounts')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    try {
      await apiPost('/api/accounts', { name })
      setName('')
      setCreating(false)
      load()
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Failed to create account')
    }
  }

  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Accounts</h1>
        <button onClick={() => setCreating((v) => !v)}>
          {creating ? 'Cancel' : '+ New Account'}
        </button>
      </div>

      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      {creating && (
        <div className="card">
          <div className="card-title">New Account</div>
          <form onSubmit={handleCreate}>
            <div className="form-group">
              <label>Account Name</label>
              <input value={name} onChange={(e) => setName(e.target.value)} required placeholder="Acme Corp" />
            </div>
            <div className="form-actions">
              <button type="submit">Create</button>
              <button type="button" className="btn-secondary" onClick={() => setCreating(false)}>Cancel</button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        {loading ? <div className="empty">Loading…</div> : (
          <DataTable
            columns={[
              { key: 'name', label: 'Name' },
              { key: 'createdAt', label: 'Created', render: (v) => new Date(v as string).toLocaleDateString() },
            ]}
            rows={accounts as unknown as Record<string, unknown>[]}
            onRowClick={(row) => navigate(`/crm/accounts/${row.id}`)}
            emptyText="No accounts yet"
          />
        )}
      </div>
    </div>
  )
}
