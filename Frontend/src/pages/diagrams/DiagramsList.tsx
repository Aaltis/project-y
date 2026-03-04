import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { apiGet, apiPost, apiDelete, ApiError } from '../../api'
import DataTable from '../../components/DataTable'
import ErrorBanner from '../../components/ErrorBanner'

interface Diagram {
  id: string
  name: string
  ownerId: string
  createdAt: string
  updatedAt: string
}

export default function DiagramsList() {
  const navigate = useNavigate()
  const [diagrams, setDiagrams] = useState<Diagram[]>([])
  const [error, setError] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [name, setName] = useState('')
  const [deleting, setDeleting] = useState<string | null>(null)

  async function load() {
    try {
      const data = await apiGet<Diagram[]>('/api/diagrams')
      setDiagrams(Array.isArray(data) ? data : [])
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Failed to load diagrams')
    }
  }

  useEffect(() => { load() }, [])

  async function create(e: React.FormEvent) {
    e.preventDefault()
    try {
      const d = await apiPost<Diagram>('/api/diagrams', { name })
      setName('')
      setShowForm(false)
      navigate(`/diagrams/${d.id}`)
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Failed to create diagram')
    }
  }

  async function remove(id: string) {
    if (!confirm('Delete this diagram?')) return
    setDeleting(id)
    try {
      await apiDelete(`/api/diagrams/${id}`)
      setDiagrams((prev) => prev.filter((d) => d.id !== id))
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Failed to delete')
    } finally {
      setDeleting(null)
    }
  }

  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Diagrams</h1>
      </div>

      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      <div style={{ marginBottom: 12 }}>
        <button className="btn btn-secondary btn-sm" onClick={() => setShowForm((v) => !v)}>
          {showForm ? 'Cancel' : '+ New Diagram'}
        </button>
      </div>

      {showForm && (
        <div className="card" style={{ marginBottom: 16 }}>
          <form onSubmit={create}>
            <div className="form-row">
              <div className="form-group">
                <label>Diagram Name</label>
                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. CRM Overview"
                  required
                />
              </div>
            </div>
            <div className="form-actions">
              <button type="submit">Create</button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        <DataTable
          columns={[
            { key: 'name', label: 'Name' },
            {
              key: 'updatedAt',
              label: 'Last Modified',
              render: (v) => new Date(v as string).toLocaleString(),
            },
            {
              key: 'id',
              label: '',
              render: (v) => (
                <button
                  className="btn btn-secondary btn-sm"
                  style={{ color: 'var(--error)', borderColor: 'var(--error)' }}
                  disabled={deleting === (v as string)}
                  onClick={(e) => { e.stopPropagation(); remove(v as string) }}
                >
                  Delete
                </button>
              ),
            },
          ]}
          rows={diagrams as unknown as Record<string, unknown>[]}
          onRowClick={(row) => navigate(`/diagrams/${row.id}`)}
          emptyText="No diagrams yet"
        />
      </div>
    </div>
  )
}
