import { useEffect, useState } from 'react'
import { apiGet, apiPost, ApiError } from '../../../api'
import ErrorBanner from '../../../components/ErrorBanner'
import DataTable from '../../../components/DataTable'

interface Baseline { id: string; version: number; status: string; createdAt: string; scopeSnapshot: string; scheduleSnapshot: string; costSnapshot: string }

interface Props { projectId: string; isPM: boolean; isSponsor: boolean }

export default function Baselines({ projectId, isPM, isSponsor }: Props) {
  const [baselines, setBaselines] = useState<Baseline[]>([])
  const [selected, setSelected] = useState<Baseline | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    try { setBaselines(await apiGet<Baseline[]>(`/api/projects/${projectId}/baselines`)) }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  useEffect(() => { load() }, [projectId])

  async function create() {
    try { await apiPost(`/api/projects/${projectId}/baselines`); load() }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to create baseline') }
  }

  async function action(version: number, endpoint: string) {
    try { await apiPost(`/api/projects/${projectId}/baselines/${version}/${endpoint}`); load() }
    catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  return (
    <div>
      <div className="page-header">
        <h2 className="page-title">Baselines</h2>
        {isPM && <button onClick={create}>+ Snapshot Baseline</button>}
      </div>
      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      <div className="card">
        <DataTable
          columns={[
            { key: 'version', label: 'Version' },
            { key: 'status', label: 'Status', render: (v) => <span className={`badge ${v === 'APPROVED' ? 'badge-green' : v === 'SUBMITTED' ? 'badge-yellow' : 'badge-gray'}`}>{v as string}</span> },
            { key: 'createdAt', label: 'Created', render: (v) => new Date(v as string).toLocaleDateString() },
            {
              key: 'id', label: 'Actions', render: (_, row) => {
                const b = row as unknown as Baseline
                return (
                  <div style={{ display: 'flex', gap: 6 }}>
                    <button className="btn btn-secondary btn-sm" onClick={() => setSelected(b)}>View Snapshot</button>
                    {b.status === 'DRAFT' && isPM && <button className="btn btn-sm" onClick={() => action(b.version, 'submit')}>Submit</button>}
                    {b.status === 'SUBMITTED' && isSponsor && <button className="btn btn-sm" onClick={() => action(b.version, 'approve')}>Approve</button>}
                  </div>
                )
              }
            },
          ]}
          rows={baselines as unknown as Record<string, unknown>[]}
          emptyText="No baselines yet"
        />
      </div>

      {selected && (
        <div className="overlay" onClick={() => setSelected(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <button className="modal-close" onClick={() => setSelected(null)}>×</button>
            <div className="modal-title">Baseline v{selected.version} — Snapshot</div>
            {(['scopeSnapshot', 'scheduleSnapshot', 'costSnapshot'] as const).map((key) => (
              <div key={key} style={{ marginBottom: 16 }}>
                <div className="section-title">{key.replace('Snapshot', ' Snapshot')}</div>
                <pre style={{ fontSize: 11, background: 'var(--surface)', padding: 10, borderRadius: 4, overflow: 'auto', maxHeight: 200 }}>
                  {selected[key] ? JSON.stringify(JSON.parse(selected[key]), null, 2) : '—'}
                </pre>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
