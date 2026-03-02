import { useEffect, useState } from 'react'
import { apiGet, apiPost, ApiError } from '../../../api'
import ErrorBanner from '../../../components/ErrorBanner'

interface StatusReport {
  id: string; periodStart: string; periodEnd: string; summary: string
  ragScope: string; ragSchedule: string; ragCost: string
  keyRisks: string; keyIssues: string; createdAt: string
}

const RAG_COLOR: Record<string, string> = { GREEN: 'badge-green', AMBER: 'badge-yellow', RED: 'badge-red' }

interface Props { projectId: string; isPM: boolean }

export default function StatusReports({ projectId, isPM }: Props) {
  const [reports, setReports] = useState<StatusReport[]>([])
  const [error, setError] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ periodStart: '', periodEnd: '', summary: '', ragScope: 'GREEN', ragSchedule: 'GREEN', ragCost: 'GREEN', keyRisks: '', keyIssues: '' })

  async function load() {
    try { setReports(await apiGet<StatusReport[]>(`/api/projects/${projectId}/status-reports`)) }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  useEffect(() => { load() }, [projectId])

  async function create(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/status-reports`, form)
      setForm({ periodStart: '', periodEnd: '', summary: '', ragScope: 'GREEN', ragSchedule: 'GREEN', ragCost: 'GREEN', keyRisks: '', keyIssues: '' })
      setShowForm(false); load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  const field = (key: keyof typeof form) => ({ value: form[key], onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => setForm((p) => ({ ...p, [key]: e.target.value })) })

  return (
    <div>
      <div className="page-header">
        <h2 className="page-title">Status Reports</h2>
        {isPM && <button className="btn btn-secondary btn-sm" onClick={() => setShowForm((v) => !v)}>{showForm ? 'Cancel' : '+ Create Report'}</button>}
      </div>
      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      {showForm && (
        <div className="card">
          <form onSubmit={create}>
            <div className="form-row">
              <div className="form-group"><label>Period Start</label><input type="date" {...field('periodStart')} required /></div>
              <div className="form-group"><label>Period End</label><input type="date" {...field('periodEnd')} required /></div>
            </div>
            <div className="form-group"><label>Summary</label><textarea {...field('summary')} required /></div>
            <div className="form-row">
              {(['ragScope', 'ragSchedule', 'ragCost'] as const).map((f) => (
                <div key={f} className="form-group">
                  <label>{f.replace('rag', 'RAG ').replace(/([A-Z])/g, ' $1').trim()}</label>
                  <select {...field(f)}>
                    <option>GREEN</option><option>AMBER</option><option>RED</option>
                  </select>
                </div>
              ))}
            </div>
            <div className="form-row">
              <div className="form-group"><label>Key Risks</label><textarea {...field('keyRisks')} /></div>
              <div className="form-group"><label>Key Issues</label><textarea {...field('keyIssues')} /></div>
            </div>
            <div className="form-actions"><button type="submit">Create</button></div>
          </form>
        </div>
      )}

      {reports.length === 0 && !showForm && <div className="empty">No status reports yet</div>}

      {reports.map((r) => (
        <div key={r.id} className="card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
            <div>
              <div style={{ fontWeight: 700, marginBottom: 2 }}>{new Date(r.periodStart).toLocaleDateString()} – {new Date(r.periodEnd).toLocaleDateString()}</div>
              <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Created {new Date(r.createdAt).toLocaleDateString()}</div>
            </div>
            <div style={{ display: 'flex', gap: 6 }}>
              <span className={`badge ${RAG_COLOR[r.ragScope]}`}>Scope</span>
              <span className={`badge ${RAG_COLOR[r.ragSchedule]}`}>Schedule</span>
              <span className={`badge ${RAG_COLOR[r.ragCost]}`}>Cost</span>
            </div>
          </div>
          <p style={{ whiteSpace: 'pre-wrap', marginBottom: 8 }}>{r.summary}</p>
          {r.keyRisks && <div style={{ fontSize: 12 }}><strong>Risks:</strong> {r.keyRisks}</div>}
          {r.keyIssues && <div style={{ fontSize: 12 }}><strong>Issues:</strong> {r.keyIssues}</div>}
        </div>
      ))}
    </div>
  )
}
