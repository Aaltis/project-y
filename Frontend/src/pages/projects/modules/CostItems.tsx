import { useEffect, useState } from 'react'
import { apiGet, apiPost, ApiError } from '../../../api'
import ErrorBanner from '../../../components/ErrorBanner'
import DataTable from '../../../components/DataTable'

interface CostItem { id: string; category: string; plannedCost: number; actualCost: number | null; wbsItemId: string | null }
interface WbsItem { id: string; name: string; wbsCode: string }

interface Props { projectId: string; isPM: boolean }

export default function CostItems({ projectId, isPM }: Props) {
  const [items, setItems] = useState<CostItem[]>([])
  const [wbsItems, setWbsItems] = useState<WbsItem[]>([])
  const [error, setError] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [category, setCategory] = useState('')
  const [planned, setPlanned] = useState('')
  const [actual, setActual] = useState('')
  const [wbsId, setWbsId] = useState('')

  async function load() {
    try {
      const [ci, wbs] = await Promise.all([
        apiGet<CostItem[]>(`/api/projects/${projectId}/cost-items`),
        apiGet<WbsItem[]>(`/api/projects/${projectId}/wbs`),
      ])
      setItems(ci); setWbsItems(wbs)
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  useEffect(() => { load() }, [projectId])

  async function create(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/cost-items`, {
        category, plannedCost: parseFloat(planned),
        actualCost: actual ? parseFloat(actual) : null,
        wbsItemId: wbsId || null,
      })
      setCategory(''); setPlanned(''); setActual(''); setWbsId(''); setShowForm(false); load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  const totalPlanned = items.reduce((s, i) => s + i.plannedCost, 0)
  const totalActual = items.reduce((s, i) => s + (i.actualCost ?? 0), 0)

  return (
    <div>
      <div className="page-header">
        <h2 className="page-title">Cost Items</h2>
        {isPM && <button className="btn btn-secondary btn-sm" onClick={() => setShowForm((v) => !v)}>{showForm ? 'Cancel' : '+ Add Cost Item'}</button>}
      </div>

      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      {showForm && (
        <div className="card">
          <form onSubmit={create}>
            <div className="form-row">
              <div className="form-group"><label>Category</label><input value={category} onChange={(e) => setCategory(e.target.value)} required placeholder="Labour, Equipment…" /></div>
              <div className="form-group"><label>Planned Cost (€)</label><input type="number" step="0.01" value={planned} onChange={(e) => setPlanned(e.target.value)} required /></div>
              <div className="form-group"><label>Actual Cost (€)</label><input type="number" step="0.01" value={actual} onChange={(e) => setActual(e.target.value)} /></div>
            </div>
            <div className="form-group">
              <label>WBS Item</label>
              <select value={wbsId} onChange={(e) => setWbsId(e.target.value)}>
                <option value="">— none —</option>
                {wbsItems.map((w) => <option key={w.id} value={w.id}>{w.wbsCode} {w.name}</option>)}
              </select>
            </div>
            <div className="form-actions"><button type="submit">Add</button></div>
          </form>
        </div>
      )}

      {items.length > 0 && (
        <div className="card" style={{ padding: '12px 20px', marginBottom: 8 }}>
          <span style={{ marginRight: 24 }}>Total planned: <strong>€{totalPlanned.toLocaleString()}</strong></span>
          <span>Total actual: <strong>€{totalActual.toLocaleString()}</strong></span>
        </div>
      )}

      <div className="card">
        <DataTable
          columns={[
            { key: 'category', label: 'Category' },
            { key: 'plannedCost', label: 'Planned', render: (v) => `€${(v as number).toLocaleString()}` },
            { key: 'actualCost', label: 'Actual', render: (v) => v != null ? `€${(v as number).toLocaleString()}` : '—' },
          ]}
          rows={items as unknown as Record<string, unknown>[]}
          emptyText="No cost items"
        />
      </div>
    </div>
  )
}
