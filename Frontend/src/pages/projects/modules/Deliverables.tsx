import { useEffect, useState } from 'react'
import { apiGet, apiPost, ApiError } from '../../../api'
import ErrorBanner from '../../../components/ErrorBanner'
import DataTable from '../../../components/DataTable'

interface Deliverable { id: string; name: string; status: string; dueDate: string | null; acceptanceCriteria: string }

const STATUS_BADGE: Record<string, string> = { PLANNED: 'badge-gray', SUBMITTED: 'badge-yellow', ACCEPTED: 'badge-green', REJECTED: 'badge-red' }

interface Props { projectId: string; isPM: boolean; isSponsor: boolean; isQA: boolean }

export default function Deliverables({ projectId, isPM, isSponsor, isQA }: Props) {
  const [deliverables, setDeliverables] = useState<Deliverable[]>([])
  const [error, setError] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [name, setName] = useState(''); const [dueDate, setDueDate] = useState(''); const [criteria, setCriteria] = useState('')

  async function load() {
    try { setDeliverables(await apiGet<Deliverable[]>(`/api/projects/${projectId}/deliverables`)) }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  useEffect(() => { load() }, [projectId])

  async function create(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/deliverables`, { name, dueDate: dueDate || null, acceptanceCriteria: criteria })
      setName(''); setDueDate(''); setCriteria(''); setShowForm(false); load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  async function action(id: string, endpoint: string) {
    try { await apiPost(`/api/projects/${projectId}/deliverables/${id}/${endpoint}`); load() }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  const canApprove = isSponsor || isQA

  return (
    <div>
      <div className="page-header">
        <h2 className="page-title">Deliverables</h2>
        {isPM && <button className="btn btn-secondary btn-sm" onClick={() => setShowForm((v) => !v)}>{showForm ? 'Cancel' : '+ Add Deliverable'}</button>}
      </div>
      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      {showForm && (
        <div className="card">
          <form onSubmit={create}>
            <div className="form-row">
              <div className="form-group"><label>Name</label><input value={name} onChange={(e) => setName(e.target.value)} required /></div>
              <div className="form-group"><label>Due Date</label><input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} /></div>
            </div>
            <div className="form-group"><label>Acceptance Criteria</label><textarea value={criteria} onChange={(e) => setCriteria(e.target.value)} /></div>
            <div className="form-actions"><button type="submit">Add</button></div>
          </form>
        </div>
      )}

      <div className="card">
        <DataTable
          columns={[
            { key: 'name', label: 'Name' },
            { key: 'status', label: 'Status', render: (v) => <span className={`badge ${STATUS_BADGE[v as string] ?? 'badge-gray'}`}>{v as string}</span> },
            { key: 'dueDate', label: 'Due', render: (v) => v ? new Date(v as string).toLocaleDateString() : '—' },
            {
              key: 'id', label: 'Actions', render: (did, row) => {
                const status = row.status as string
                return (
                  <div style={{ display: 'flex', gap: 6 }}>
                    {status === 'PLANNED' && <button className="btn btn-sm btn-secondary" onClick={() => action(did as string, 'submit')}>Submit</button>}
                    {status === 'SUBMITTED' && canApprove && (
                      <>
                        <button className="btn btn-sm" onClick={() => action(did as string, 'accept')}>Accept</button>
                        <button className="btn btn-sm btn-danger" onClick={() => action(did as string, 'reject')}>Reject</button>
                      </>
                    )}
                  </div>
                )
              }
            },
          ]}
          rows={deliverables as unknown as Record<string, unknown>[]}
          emptyText="No deliverables"
        />
      </div>
    </div>
  )
}
