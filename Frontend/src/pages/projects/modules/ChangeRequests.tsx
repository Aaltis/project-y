import { useEffect, useState } from 'react'
import { apiGet, apiPost, ApiError } from '../../../api'
import ErrorBanner from '../../../components/ErrorBanner'
import DataTable from '../../../components/DataTable'

interface CR { id: string; type: string; description: string; status: string; submittedBy: string; createdAt: string; impactScope: string; impactScheduleDays: number | null; impactCost: number | null }

const CR_TYPES = ['SCOPE', 'SCHEDULE', 'COST', 'QUALITY', 'RISK']
const STATUS_BADGE: Record<string, string> = {
  DRAFT: 'badge-gray', SUBMITTED: 'badge-blue', IN_REVIEW: 'badge-yellow',
  APPROVED: 'badge-green', REJECTED: 'badge-red', IMPLEMENTED: 'badge-blue',
}

interface Props { projectId: string; isPM: boolean; isSponsor: boolean }

export default function ChangeRequests({ projectId, isPM, isSponsor }: Props) {
  const [crs, setCrs] = useState<CR[]>([])
  const [error, setError] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [type, setType] = useState('SCOPE'); const [desc, setDesc] = useState(''); const [scope, setScope] = useState(''); const [days, setDays] = useState(''); const [cost, setCost] = useState('')

  async function load() {
    try { setCrs(await apiGet<CR[]>(`/api/projects/${projectId}/change-requests`)) }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  useEffect(() => { load() }, [projectId])

  async function create(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/change-requests`, { type, description: desc, impactScope: scope, impactScheduleDays: days ? parseInt(days) : null, impactCost: cost ? parseFloat(cost) : null })
      setDesc(''); setScope(''); setDays(''); setCost(''); setShowForm(false); load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  async function action(id: string, endpoint: string) {
    try { await apiPost(`/api/projects/${projectId}/change-requests/${id}/${endpoint}`); load() }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  const canApprove = isPM || isSponsor

  return (
    <div>
      <div className="page-header">
        <h2 className="page-title">Change Requests</h2>
        <button className="btn btn-secondary btn-sm" onClick={() => setShowForm((v) => !v)}>{showForm ? 'Cancel' : '+ New CR'}</button>
      </div>
      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      {showForm && (
        <div className="card">
          <form onSubmit={create}>
            <div className="form-row">
              <div className="form-group" style={{ flex: '0 0 140px' }}>
                <label>Type</label>
                <select value={type} onChange={(e) => setType(e.target.value)}>{CR_TYPES.map((t) => <option key={t}>{t}</option>)}</select>
              </div>
              <div className="form-group"><label>Description</label><input value={desc} onChange={(e) => setDesc(e.target.value)} required /></div>
            </div>
            <div className="form-row">
              <div className="form-group"><label>Impact Scope</label><input value={scope} onChange={(e) => setScope(e.target.value)} /></div>
              <div className="form-group"><label>Schedule Impact (days)</label><input type="number" value={days} onChange={(e) => setDays(e.target.value)} /></div>
              <div className="form-group"><label>Cost Impact (€)</label><input type="number" step="0.01" value={cost} onChange={(e) => setCost(e.target.value)} /></div>
            </div>
            <div className="form-actions"><button type="submit">Create DRAFT</button></div>
          </form>
        </div>
      )}

      <div className="card">
        <DataTable
          columns={[
            { key: 'type', label: 'Type', render: (v) => <span className="badge badge-gray">{v as string}</span> },
            { key: 'description', label: 'Description' },
            { key: 'status', label: 'Status', render: (v) => <span className={`badge ${STATUS_BADGE[v as string] ?? 'badge-gray'}`}>{v as string}</span> },
            { key: 'createdAt', label: 'Created', render: (v) => new Date(v as string).toLocaleDateString() },
            {
              key: 'id', label: 'Actions', render: (id, row) => {
                const status = row.status as string
                return (
                  <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                    {status === 'DRAFT' && <button className="btn btn-sm btn-secondary" onClick={() => action(id as string, 'submit')}>Submit</button>}
                    {status === 'SUBMITTED' && isPM && <button className="btn btn-sm btn-secondary" onClick={() => action(id as string, 'review')}>Review</button>}
                    {status === 'IN_REVIEW' && canApprove && (
                      <>
                        <button className="btn btn-sm" onClick={() => action(id as string, 'approve')}>Approve</button>
                        <button className="btn btn-sm btn-danger" onClick={() => action(id as string, 'reject')}>Reject</button>
                      </>
                    )}
                    {status === 'APPROVED' && isPM && <button className="btn btn-sm btn-secondary" onClick={() => action(id as string, 'implement')}>Mark Implemented</button>}
                  </div>
                )
              }
            },
          ]}
          rows={crs as unknown as Record<string, unknown>[]}
          emptyText="No change requests"
        />
      </div>
    </div>
  )
}
