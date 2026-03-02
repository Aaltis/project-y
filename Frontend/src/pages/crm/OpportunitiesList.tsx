import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { apiGet, ApiError } from '../../api'
import DataTable from '../../components/DataTable'
import ErrorBanner from '../../components/ErrorBanner'

interface Opportunity {
  id: string; name: string; stage: string; amount: number | null; closeDate: string | null; ownerId: string
}

const STAGES = ['PROSPECT', 'QUALIFY', 'PROPOSE', 'NEGOTIATE', 'WON', 'LOST']

const STAGE_BADGE: Record<string, string> = {
  PROSPECT: 'badge-gray', QUALIFY: 'badge-blue', PROPOSE: 'badge-blue',
  NEGOTIATE: 'badge-yellow', WON: 'badge-green', LOST: 'badge-red',
}

export default function OpportunitiesList() {
  const navigate = useNavigate()
  const [opportunities, setOpportunities] = useState<Opportunity[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [mine, setMine] = useState(false)
  const [stage, setStage] = useState('')
  const [closingBefore, setClosingBefore] = useState('')

  async function load() {
    setLoading(true)
    try {
      const params = new URLSearchParams()
      if (mine) params.set('mine', 'true')
      if (stage) params.set('stage', stage)
      if (closingBefore) params.set('closingBefore', closingBefore)
      params.set('size', '100')
      const data = await apiGet<{ content: Opportunity[] } | Opportunity[]>(`/api/opportunities?${params}`)
      setOpportunities(Array.isArray(data) ? data : data.content)
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Failed to load')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [mine, stage, closingBefore])

  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Opportunities</h1>
      </div>

      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      <div className="card" style={{ padding: '14px 20px' }}>
        <div style={{ display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap' }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: 6, textTransform: 'none', letterSpacing: 0, fontSize: 13 }}>
            <input type="checkbox" checked={mine} onChange={(e) => setMine(e.target.checked)} style={{ width: 'auto' }} />
            Mine only
          </label>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <label style={{ margin: 0 }}>Stage</label>
            <select value={stage} onChange={(e) => setStage(e.target.value)} style={{ width: 140 }}>
              <option value="">All stages</option>
              {STAGES.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <label style={{ margin: 0 }}>Closing before</label>
            <input type="date" value={closingBefore} onChange={(e) => setClosingBefore(e.target.value)} style={{ width: 160 }} />
          </div>
          {(mine || stage || closingBefore) && (
            <button className="btn btn-secondary btn-sm" onClick={() => { setMine(false); setStage(''); setClosingBefore('') }}>
              Clear filters
            </button>
          )}
        </div>
      </div>

      <div className="card">
        {loading ? <div className="empty">Loading…</div> : (
          <DataTable
            columns={[
              { key: 'name', label: 'Name' },
              { key: 'stage', label: 'Stage', render: (v) => <span className={`badge ${STAGE_BADGE[v as string] ?? 'badge-gray'}`}>{v as string}</span> },
              { key: 'amount', label: 'Amount', render: (v) => v ? `€${(v as number).toLocaleString()}` : '—' },
              { key: 'closeDate', label: 'Close Date', render: (v) => v ? new Date(v as string).toLocaleDateString() : '—' },
            ]}
            rows={opportunities as unknown as Record<string, unknown>[]}
            onRowClick={(row) => navigate(`/crm/opportunities/${row.id}`)}
            emptyText="No opportunities match the current filters"
          />
        )}
      </div>
    </div>
  )
}
