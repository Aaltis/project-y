import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { apiGet, apiPost, apiPut, ApiError } from '../../api'
import ErrorBanner from '../../components/ErrorBanner'
import DataTable from '../../components/DataTable'

interface Opportunity {
  id: string; name: string; stage: string
  amount: number | null; closeDate: string | null; accountId: string; ownerId: string
}
interface Activity { id: string; type: string; text: string; dueAt: string | null; createdAt: string }

const STAGE_TRANSITIONS: Record<string, string[]> = {
  PROSPECT: ['QUALIFY', 'LOST'],
  QUALIFY: ['PROPOSE', 'LOST'],
  PROPOSE: ['NEGOTIATE', 'LOST'],
  NEGOTIATE: ['WON', 'LOST'],
  WON: [],
  LOST: [],
}
const STAGE_BADGE: Record<string, string> = {
  PROSPECT: 'badge-gray', QUALIFY: 'badge-blue', PROPOSE: 'badge-blue',
  NEGOTIATE: 'badge-yellow', WON: 'badge-green', LOST: 'badge-red',
}
const ACTIVITY_TYPES = ['NOTE', 'CALL', 'MEETING', 'TASK']

export default function OpportunityDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [opp, setOpp] = useState<Opportunity | null>(null)
  const [activities, setActivities] = useState<Activity[]>([])
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState(false)
  const [editName, setEditName] = useState('')
  const [editAmount, setEditAmount] = useState('')
  const [editCloseDate, setEditCloseDate] = useState('')
  const [showActivityForm, setShowActivityForm] = useState(false)
  const [actType, setActType] = useState('NOTE')
  const [actText, setActText] = useState('')
  const [actDue, setActDue] = useState('')

  async function loadAll() {
    try {
      const [o, acts] = await Promise.all([
        apiGet<Opportunity>(`/api/opportunities/${id}`),
        apiGet<Activity[]>(`/api/opportunities/${id}/activities`),
      ])
      setOpp(o)
      setActivities(acts)
      setEditName(o.name)
      setEditAmount(o.amount != null ? String(o.amount) : '')
      setEditCloseDate(o.closeDate ?? '')
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to load') }
  }

  useEffect(() => { loadAll() }, [id])

  async function saveEdit(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPut(`/api/opportunities/${id}`, {
        name: editName,
        amount: editAmount ? parseFloat(editAmount) : null,
        closeDate: editCloseDate || null,
      })
      setEditing(false)
      loadAll()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to save') }
  }

  async function advanceStage(nextStage: string) {
    if (nextStage === 'WON' && (!opp?.amount || !opp?.closeDate)) {
      setError('Set amount and close date before advancing to WON')
      return
    }
    try {
      await apiPost(`/api/opportunities/${id}/stage`, { stage: nextStage })
      loadAll()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Stage transition failed') }
  }

  async function createActivity(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/opportunities/${id}/activities`, { type: actType, text: actText, dueAt: actDue || null })
      setActText(''); setActDue(''); setActType('NOTE'); setShowActivityForm(false)
      loadAll()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to create activity') }
  }

  if (!opp) return <div className="page"><div className="empty">Loading…</div></div>

  const nextStages = STAGE_TRANSITIONS[opp.stage] ?? []

  return (
    <div className="page">
      <button className="btn btn-secondary btn-sm" style={{ marginBottom: 12 }} onClick={() => navigate(-1)}>← Back</button>

      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      <div className="card">
        <div className="page-header" style={{ marginBottom: 0 }}>
          <div>
            <h1 className="page-title">{opp.name}</h1>
            <span className={`badge ${STAGE_BADGE[opp.stage] ?? 'badge-gray'}`} style={{ marginTop: 4, display: 'inline-block' }}>
              {opp.stage}
            </span>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            {nextStages.map((s) => (
              <button
                key={s}
                className={s === 'LOST' ? 'btn btn-danger btn-sm' : 'btn btn-sm'}
                onClick={() => advanceStage(s)}
              >
                → {s}
              </button>
            ))}
            <button className="btn btn-secondary btn-sm" onClick={() => setEditing((v) => !v)}>
              {editing ? 'Cancel' : 'Edit'}
            </button>
          </div>
        </div>

        {!editing && (
          <div style={{ marginTop: 16, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <div><span style={{ color: 'var(--text-muted)', fontSize: 12 }}>Amount</span><div>{opp.amount != null ? `€${opp.amount.toLocaleString()}` : '—'}</div></div>
            <div><span style={{ color: 'var(--text-muted)', fontSize: 12 }}>Close Date</span><div>{opp.closeDate ? new Date(opp.closeDate).toLocaleDateString() : '—'}</div></div>
          </div>
        )}

        {editing && (
          <form onSubmit={saveEdit} style={{ marginTop: 16 }}>
            <div className="form-row">
              <div className="form-group"><label>Name</label><input value={editName} onChange={(e) => setEditName(e.target.value)} required /></div>
              <div className="form-group"><label>Amount (€)</label><input type="number" step="0.01" value={editAmount} onChange={(e) => setEditAmount(e.target.value)} /></div>
              <div className="form-group"><label>Close Date</label><input type="date" value={editCloseDate} onChange={(e) => setEditCloseDate(e.target.value)} /></div>
            </div>
            <div className="form-actions"><button type="submit">Save</button><button type="button" className="btn btn-secondary" onClick={() => setEditing(false)}>Cancel</button></div>
          </form>
        )}
      </div>

      {/* Activities */}
      <div className="section">
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <div className="section-title">Activities</div>
          <button className="btn btn-secondary btn-sm" onClick={() => setShowActivityForm((v) => !v)}>
            {showActivityForm ? 'Cancel' : '+ Add Activity'}
          </button>
        </div>

        {showActivityForm && (
          <div className="card">
            <form onSubmit={createActivity}>
              <div className="form-row">
                <div className="form-group" style={{ flex: '0 0 120px' }}>
                  <label>Type</label>
                  <select value={actType} onChange={(e) => setActType(e.target.value)}>
                    {ACTIVITY_TYPES.map((t) => <option key={t}>{t}</option>)}
                  </select>
                </div>
                <div className="form-group"><label>Text</label><input value={actText} onChange={(e) => setActText(e.target.value)} required /></div>
                <div className="form-group" style={{ flex: '0 0 170px' }}><label>Due At</label><input type="datetime-local" value={actDue} onChange={(e) => setActDue(e.target.value)} /></div>
              </div>
              <div className="form-actions"><button type="submit">Add</button></div>
            </form>
          </div>
        )}

        <div className="card">
          <DataTable
            columns={[
              { key: 'type', label: 'Type', render: (v) => <span className="badge badge-gray">{v as string}</span> },
              { key: 'text', label: 'Text' },
              { key: 'dueAt', label: 'Due', render: (v) => v ? new Date(v as string).toLocaleString() : '—' },
              { key: 'createdAt', label: 'Created', render: (v) => new Date(v as string).toLocaleString() },
            ]}
            rows={activities as unknown as Record<string, unknown>[]}
            emptyText="No activities yet"
          />
        </div>
      </div>
    </div>
  )
}
