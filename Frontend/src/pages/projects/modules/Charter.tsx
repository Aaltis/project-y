import { useEffect, useState } from 'react'
import { apiGet, apiPost, ApiError } from '../../../api'
import ErrorBanner from '../../../components/ErrorBanner'

interface Charter {
  id: string; projectId: string; objectives: string; highLevelScope: string
  successCriteria: string; summaryBudget: number | null; keyRisks: string; status: string
}

interface Props { projectId: string; isPM: boolean; isSponsor: boolean; onRefresh: () => void }

export default function Charter({ projectId, isPM, isSponsor, onRefresh }: Props) {
  const [charter, setCharter] = useState<Charter | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [creating, setCreating] = useState(false)
  const [form, setForm] = useState({ objectives: '', highLevelScope: '', successCriteria: '', summaryBudget: '', keyRisks: '' })

  async function load() {
    try {
      const data = await apiGet<Charter>(`/api/projects/${projectId}/charter`)
      setCharter(data)
    } catch (e) {
      if (e instanceof ApiError && e.status === 404) setCharter(null)
      else setError(e instanceof ApiError ? e.message : 'Failed to load')
    } finally { setLoading(false) }
  }

  useEffect(() => { load() }, [projectId])

  async function create(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/charter`, {
        ...form, summaryBudget: form.summaryBudget ? parseFloat(form.summaryBudget) : null,
      })
      setCreating(false)
      load(); onRefresh()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  async function action(endpoint: string) {
    try {
      await apiPost(`/api/projects/${projectId}/charter/${endpoint}`)
      load(); onRefresh()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  if (loading) return <div className="empty">Loading…</div>

  return (
    <div>
      <div className="page-header">
        <h2 className="page-title">Project Charter</h2>
        {!charter && isPM && <button onClick={() => setCreating(true)}>+ Create Charter</button>}
      </div>

      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      {!charter && !creating && <div className="empty">No charter yet. PM can create one.</div>}

      {creating && (
        <div className="card">
          <div className="card-title">New Charter</div>
          <form onSubmit={create}>
            {(['objectives', 'highLevelScope', 'successCriteria', 'keyRisks'] as const).map((f) => (
              <div key={f} className="form-group">
                <label>{f.replace(/([A-Z])/g, ' $1').trim()}</label>
                <textarea value={form[f]} onChange={(e) => setForm((p) => ({ ...p, [f]: e.target.value }))} required={f === 'objectives'} />
              </div>
            ))}
            <div className="form-group">
              <label>Summary Budget</label>
              <input type="number" step="0.01" value={form.summaryBudget} onChange={(e) => setForm((p) => ({ ...p, summaryBudget: e.target.value }))} />
            </div>
            <div className="form-actions">
              <button type="submit">Create</button>
              <button type="button" className="btn btn-secondary" onClick={() => setCreating(false)}>Cancel</button>
            </div>
          </form>
        </div>
      )}

      {charter && (
        <div className="card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
            <span className={`badge ${charter.status === 'APPROVED' ? 'badge-green' : charter.status === 'SUBMITTED' ? 'badge-yellow' : 'badge-gray'}`}>
              {charter.status}
            </span>
            <div style={{ display: 'flex', gap: 8 }}>
              {charter.status === 'DRAFT' && isPM && (
                <button className="btn btn-sm" onClick={() => action('submit')}>Submit for Approval</button>
              )}
              {charter.status === 'SUBMITTED' && isSponsor && (
                <button className="btn btn-sm" onClick={() => action('approve')}>Approve</button>
              )}
            </div>
          </div>
          {[
            ['Objectives', charter.objectives],
            ['High Level Scope', charter.highLevelScope],
            ['Success Criteria', charter.successCriteria],
            ['Key Risks', charter.keyRisks],
            ['Summary Budget', charter.summaryBudget != null ? `€${charter.summaryBudget.toLocaleString()}` : '—'],
          ].map(([label, value]) => (
            <div key={label} style={{ marginBottom: 12 }}>
              <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 2 }}>{label}</div>
              <div style={{ whiteSpace: 'pre-wrap' }}>{value || '—'}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
