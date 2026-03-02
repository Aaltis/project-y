import { useEffect, useState } from 'react'
import { apiGet, apiPost, ApiError } from '../../../api'
import ErrorBanner from '../../../components/ErrorBanner'
import DataTable from '../../../components/DataTable'

interface Decision { id: string; decision: string; decisionDate: string; madeBy: string }

interface Props { projectId: string; isPM: boolean }

export default function DecisionLog({ projectId, isPM }: Props) {
  const [decisions, setDecisions] = useState<Decision[]>([])
  const [error, setError] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [decision, setDecision] = useState('')
  const [decisionDate, setDecisionDate] = useState(new Date().toISOString().slice(0, 10))

  async function load() {
    try { setDecisions(await apiGet<Decision[]>(`/api/projects/${projectId}/decisions`)) }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  useEffect(() => { load() }, [projectId])

  async function create(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/decisions`, { decision, decisionDate })
      setDecision(''); setShowForm(false); load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  return (
    <div>
      <div className="page-header">
        <h2 className="page-title">Decision Log</h2>
        {isPM && <button className="btn btn-secondary btn-sm" onClick={() => setShowForm((v) => !v)}>{showForm ? 'Cancel' : '+ Add Decision'}</button>}
      </div>
      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      {showForm && (
        <div className="card">
          <form onSubmit={create}>
            <div className="form-group"><label>Decision</label><textarea value={decision} onChange={(e) => setDecision(e.target.value)} required /></div>
            <div className="form-group" style={{ maxWidth: 200 }}><label>Date</label><input type="date" value={decisionDate} onChange={(e) => setDecisionDate(e.target.value)} required /></div>
            <div className="form-actions"><button type="submit">Add</button></div>
          </form>
        </div>
      )}

      <div className="card">
        <DataTable
          columns={[
            { key: 'decisionDate', label: 'Date', render: (v) => new Date(v as string).toLocaleDateString() },
            { key: 'decision', label: 'Decision' },
            { key: 'madeBy', label: 'Made By', render: (v) => <span style={{ fontFamily: 'monospace', fontSize: 11 }}>{(v as string).slice(0, 8)}…</span> },
          ]}
          rows={decisions as unknown as Record<string, unknown>[]}
          emptyText="No decisions logged"
        />
      </div>
    </div>
  )
}
