import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { apiGet, apiPost, ApiError } from '../../api'
import { getSub } from '../../keycloak'
import DataTable from '../../components/DataTable'
import ErrorBanner from '../../components/ErrorBanner'

interface Project { id: string; name: string; status: string; pmId: string; sponsorId: string; createdAt: string }

const STATUS_BADGE: Record<string, string> = { DRAFT: 'badge-gray', ACTIVE: 'badge-green', CLOSED: 'badge-blue' }

export default function ProjectsList() {
  const navigate = useNavigate()
  const [projects, setProjects] = useState<Project[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [creating, setCreating] = useState(false)
  const [name, setName] = useState('')
  const [sponsorId, setSponsorId] = useState('')
  const [startTarget, setStartTarget] = useState('')
  const [endTarget, setEndTarget] = useState('')

  async function load() {
    try {
      const data = await apiGet<Project[]>('/api/projects')
      setProjects(data)
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to load') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [])

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    try {
      await apiPost('/api/projects', {
        name,
        sponsorId: sponsorId || getSub(),
        startTarget: startTarget || null,
        endTarget: endTarget || null,
      })
      setName(''); setSponsorId(''); setStartTarget(''); setEndTarget('')
      setCreating(false)
      load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to create') }
  }

  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Projects</h1>
        <button onClick={() => setCreating((v) => !v)}>{creating ? 'Cancel' : '+ New Project'}</button>
      </div>

      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      {creating && (
        <div className="card">
          <div className="card-title">New Project</div>
          <form onSubmit={handleCreate}>
            <div className="form-row">
              <div className="form-group"><label>Project Name</label><input value={name} onChange={(e) => setName(e.target.value)} required placeholder="My Project" /></div>
              <div className="form-group">
                <label>Sponsor ID (Keycloak sub)</label>
                <input value={sponsorId} onChange={(e) => setSponsorId(e.target.value)} placeholder="Leave empty to use yourself" />
              </div>
            </div>
            <div className="form-row">
              <div className="form-group"><label>Start Target</label><input type="date" value={startTarget} onChange={(e) => setStartTarget(e.target.value)} /></div>
              <div className="form-group"><label>End Target</label><input type="date" value={endTarget} onChange={(e) => setEndTarget(e.target.value)} /></div>
            </div>
            <p style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 12 }}>
              You will become PM automatically. Sponsor ID defaults to your own Keycloak sub ({getSub()}) if left blank.
            </p>
            <div className="form-actions">
              <button type="submit">Create</button>
              <button type="button" className="btn btn-secondary" onClick={() => setCreating(false)}>Cancel</button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        {loading ? <div className="empty">Loading…</div> : (
          <DataTable
            columns={[
              { key: 'name', label: 'Name' },
              { key: 'status', label: 'Status', render: (v) => <span className={`badge ${STATUS_BADGE[v as string] ?? 'badge-gray'}`}>{v as string}</span> },
              { key: 'createdAt', label: 'Created', render: (v) => new Date(v as string).toLocaleDateString() },
            ]}
            rows={projects as unknown as Record<string, unknown>[]}
            onRowClick={(row) => navigate(`/projects/${row.id}`)}
            emptyText="No projects yet"
          />
        )}
      </div>
    </div>
  )
}
