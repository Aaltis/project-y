import { useEffect, useState } from 'react'
import { apiGet, apiPost, ApiError } from '../../../api'
import ErrorBanner from '../../../components/ErrorBanner'
import DataTable from '../../../components/DataTable'
import { Project } from '../ProjectWorkspace'

interface ClosureReport {
  id: string; projectId: string; outcomesSummary: string; budgetActual: number | null
  scheduleActual: string; acceptanceSummary: string; status: string
}
interface Lesson { id: string; category: string; whatHappened: string; recommendation: string; createdAt: string }

interface Props { projectId: string; project: Project; isPM: boolean; isSponsor: boolean; onRefresh: () => void }

export default function Closing({ projectId, project, isPM, isSponsor, onRefresh }: Props) {
  const [report, setReport] = useState<ClosureReport | null>(null)
  const [lessons, setLessons] = useState<Lesson[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [showReportForm, setShowReportForm] = useState(false)
  const [showLessonForm, setShowLessonForm] = useState(false)
  const [rForm, setRForm] = useState({ outcomesSummary: '', budgetActual: '', scheduleActual: '', acceptanceSummary: '' })
  const [lForm, setLForm] = useState({ category: '', whatHappened: '', recommendation: '' })

  async function load() {
    try {
      const [ls] = await Promise.all([
        apiGet<Lesson[]>(`/api/projects/${projectId}/lessons-learned`),
      ])
      setLessons(ls)
      try {
        const r = await apiGet<ClosureReport>(`/api/projects/${projectId}/closure-report`)
        setReport(r)
      } catch (e) {
        if (e instanceof ApiError && e.status === 404) setReport(null)
        else throw e
      }
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [projectId])

  async function createReport(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/closure-report`, { ...rForm, budgetActual: rForm.budgetActual ? parseFloat(rForm.budgetActual) : null })
      setShowReportForm(false); load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  async function reportAction(endpoint: string, body?: unknown) {
    try {
      await apiPost(`/api/projects/${projectId}/closure-report/${endpoint}`, body)
      load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  async function closeProject() {
    if (!confirm('Close project? Gate conditions must be met (closure report APPROVED + all deliverables ACCEPTED).')) return
    try { await apiPost(`/api/projects/${projectId}/close`); onRefresh(); load() }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to close project') }
  }

  async function addLesson(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/lessons-learned`, lForm)
      setLForm({ category: '', whatHappened: '', recommendation: '' }); setShowLessonForm(false); load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  if (loading) return <div className="empty">Loading…</div>

  const isClosed = project.status === 'CLOSED'

  return (
    <div>
      <div className="page-header">
        <h2 className="page-title">Closing</h2>
        {project.status === 'ACTIVE' && isPM && report?.status === 'APPROVED' && (
          <button className="btn btn-danger" onClick={closeProject}>Close Project</button>
        )}
      </div>

      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}
      {isClosed && <div className="card" style={{ background: '#f0fdf4', borderColor: '#86efac' }}><strong>Project is CLOSED.</strong></div>}

      {/* Closure Report */}
      <div className="section">
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <div className="section-title">Closure Report</div>
          {!report && isPM && !isClosed && <button className="btn btn-secondary btn-sm" onClick={() => setShowReportForm((v) => !v)}>{showReportForm ? 'Cancel' : '+ Create'}</button>}
        </div>

        {showReportForm && (
          <div className="card">
            <form onSubmit={createReport}>
              <div className="form-group"><label>Outcomes Summary</label><textarea value={rForm.outcomesSummary} onChange={(e) => setRForm((p) => ({ ...p, outcomesSummary: e.target.value }))} required /></div>
              <div className="form-row">
                <div className="form-group"><label>Budget Actual (€)</label><input type="number" step="0.01" value={rForm.budgetActual} onChange={(e) => setRForm((p) => ({ ...p, budgetActual: e.target.value }))} /></div>
                <div className="form-group"><label>Schedule Actual</label><input value={rForm.scheduleActual} onChange={(e) => setRForm((p) => ({ ...p, scheduleActual: e.target.value }))} /></div>
              </div>
              <div className="form-group"><label>Acceptance Summary (note any waivers here)</label><textarea value={rForm.acceptanceSummary} onChange={(e) => setRForm((p) => ({ ...p, acceptanceSummary: e.target.value }))} /></div>
              <div className="form-actions"><button type="submit">Create DRAFT</button></div>
            </form>
          </div>
        )}

        {!report && !showReportForm && <div className="empty">No closure report yet.</div>}

        {report && (
          <div className="card">
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
              <span className={`badge ${report.status === 'APPROVED' ? 'badge-green' : report.status === 'SUBMITTED' ? 'badge-yellow' : 'badge-gray'}`}>{report.status}</span>
              <div style={{ display: 'flex', gap: 8 }}>
                {report.status === 'DRAFT' && isPM && <button className="btn btn-sm" onClick={() => reportAction('submit')}>Submit</button>}
                {report.status === 'SUBMITTED' && isSponsor && <button className="btn btn-sm" onClick={() => reportAction('approve')}>Approve</button>}
              </div>
            </div>
            {[
              ['Outcomes Summary', report.outcomesSummary],
              ['Budget Actual', report.budgetActual != null ? `€${report.budgetActual.toLocaleString()}` : '—'],
              ['Schedule Actual', report.scheduleActual],
              ['Acceptance Summary', report.acceptanceSummary],
            ].map(([label, value]) => (
              <div key={label} style={{ marginBottom: 10 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 2 }}>{label}</div>
                <div style={{ whiteSpace: 'pre-wrap' }}>{value || '—'}</div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Lessons Learned */}
      <div className="section">
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <div className="section-title">Lessons Learned</div>
          {!isClosed && <button className="btn btn-secondary btn-sm" onClick={() => setShowLessonForm((v) => !v)}>{showLessonForm ? 'Cancel' : '+ Add Lesson'}</button>}
        </div>

        {showLessonForm && (
          <div className="card">
            <form onSubmit={addLesson}>
              <div className="form-row">
                <div className="form-group" style={{ flex: '0 0 180px' }}><label>Category</label><input value={lForm.category} onChange={(e) => setLForm((p) => ({ ...p, category: e.target.value }))} placeholder="Technical, Process…" /></div>
                <div className="form-group"><label>What Happened</label><input value={lForm.whatHappened} onChange={(e) => setLForm((p) => ({ ...p, whatHappened: e.target.value }))} required /></div>
              </div>
              <div className="form-group"><label>Recommendation</label><textarea value={lForm.recommendation} onChange={(e) => setLForm((p) => ({ ...p, recommendation: e.target.value }))} /></div>
              <div className="form-actions"><button type="submit">Add</button></div>
            </form>
          </div>
        )}

        <div className="card">
          <DataTable
            columns={[
              { key: 'category', label: 'Category', render: (v) => v ? <span className="badge badge-gray">{v as string}</span> : '—' },
              { key: 'whatHappened', label: 'What Happened' },
              { key: 'recommendation', label: 'Recommendation' },
              { key: 'createdAt', label: 'Date', render: (v) => new Date(v as string).toLocaleDateString() },
            ]}
            rows={lessons as unknown as Record<string, unknown>[]}
            emptyText="No lessons recorded"
          />
        </div>
      </div>

      {project.status === 'ACTIVE' && isPM && report?.status === 'APPROVED' && (
        <div className="card" style={{ background: '#fffbeb', borderColor: '#fde68a' }}>
          <strong>Gate conditions met.</strong> The closure report is APPROVED. Verify all deliverables are ACCEPTED, then click <em>Close Project</em> above.
        </div>
      )}
    </div>
  )
}
