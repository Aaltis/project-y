import { useEffect, useState } from 'react'
import { apiGet, apiPost, apiPatch, ApiError } from '../../../api'
import ErrorBanner from '../../../components/ErrorBanner'
import DataTable from '../../../components/DataTable'

interface WbsItem { id: string; name: string; wbsCode: string; description: string }
interface Task { id: string; name: string; status: string; assigneeId: string | null; startDate: string | null; endDate: string | null; wbsItemId: string | null }

const TASK_STATUSES = ['TODO', 'IN_PROGRESS', 'DONE', 'BLOCKED']
const STATUS_BADGE: Record<string, string> = { TODO: 'badge-gray', IN_PROGRESS: 'badge-blue', DONE: 'badge-green', BLOCKED: 'badge-red' }

interface Props { projectId: string; isPM: boolean }

export default function WbsTasks({ projectId, isPM }: Props) {
  const [wbsItems, setWbsItems] = useState<WbsItem[]>([])
  const [tasks, setTasks] = useState<Task[]>([])
  const [error, setError] = useState<string | null>(null)
  const [tab, setTab] = useState<'wbs' | 'tasks'>('wbs')
  const [showWbsForm, setShowWbsForm] = useState(false)
  const [wbsName, setWbsName] = useState(''); const [wbsCode, setWbsCode] = useState(''); const [wbsDesc, setWbsDesc] = useState('')
  const [showTaskForm, setShowTaskForm] = useState(false)
  const [taskName, setTaskName] = useState(''); const [taskStart, setTaskStart] = useState(''); const [taskEnd, setTaskEnd] = useState(''); const [taskWbs, setTaskWbs] = useState('')

  async function load() {
    try {
      const [w, t] = await Promise.all([
        apiGet<WbsItem[]>(`/api/projects/${projectId}/wbs`),
        apiGet<Task[]>(`/api/projects/${projectId}/tasks`),
      ])
      setWbsItems(w); setTasks(t)
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  useEffect(() => { load() }, [projectId])

  async function createWbs(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/wbs`, { name: wbsName, wbsCode, description: wbsDesc })
      setWbsName(''); setWbsCode(''); setWbsDesc(''); setShowWbsForm(false); load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  async function createTask(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/projects/${projectId}/tasks`, { name: taskName, startDate: taskStart || null, endDate: taskEnd || null, wbsItemId: taskWbs || null })
      setTaskName(''); setTaskStart(''); setTaskEnd(''); setTaskWbs(''); setShowTaskForm(false); load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  async function updateTaskStatus(taskId: string, status: string) {
    try {
      await apiPatch(`/api/projects/${projectId}/tasks/${taskId}`, { status })
      load()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  return (
    <div>
      <h2 className="page-title" style={{ marginBottom: 16 }}>WBS &amp; Tasks</h2>
      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      <div className="tabs">
        <button className={`tab-btn ${tab === 'wbs' ? 'active' : ''}`} onClick={() => setTab('wbs')}>WBS Items ({wbsItems.length})</button>
        <button className={`tab-btn ${tab === 'tasks' ? 'active' : ''}`} onClick={() => setTab('tasks')}>Tasks ({tasks.length})</button>
      </div>

      {tab === 'wbs' && (
        <>
          {isPM && <button className="btn btn-secondary btn-sm" style={{ marginBottom: 12 }} onClick={() => setShowWbsForm((v) => !v)}>{showWbsForm ? 'Cancel' : '+ Add WBS Item'}</button>}
          {showWbsForm && (
            <div className="card">
              <form onSubmit={createWbs}>
                <div className="form-row">
                  <div className="form-group"><label>WBS Code</label><input value={wbsCode} onChange={(e) => setWbsCode(e.target.value)} placeholder="1.1.2" /></div>
                  <div className="form-group"><label>Name</label><input value={wbsName} onChange={(e) => setWbsName(e.target.value)} required /></div>
                </div>
                <div className="form-group"><label>Description</label><textarea value={wbsDesc} onChange={(e) => setWbsDesc(e.target.value)} /></div>
                <div className="form-actions"><button type="submit">Add</button></div>
              </form>
            </div>
          )}
          <div className="card">
            <DataTable
              columns={[{ key: 'wbsCode', label: 'Code' }, { key: 'name', label: 'Name' }, { key: 'description', label: 'Description' }]}
              rows={wbsItems as unknown as Record<string, unknown>[]}
              emptyText="No WBS items"
            />
          </div>
        </>
      )}

      {tab === 'tasks' && (
        <>
          {isPM && <button className="btn btn-secondary btn-sm" style={{ marginBottom: 12 }} onClick={() => setShowTaskForm((v) => !v)}>{showTaskForm ? 'Cancel' : '+ Add Task'}</button>}
          {showTaskForm && (
            <div className="card">
              <form onSubmit={createTask}>
                <div className="form-row">
                  <div className="form-group"><label>Name</label><input value={taskName} onChange={(e) => setTaskName(e.target.value)} required /></div>
                  <div className="form-group"><label>Start Date</label><input type="date" value={taskStart} onChange={(e) => setTaskStart(e.target.value)} /></div>
                  <div className="form-group"><label>End Date</label><input type="date" value={taskEnd} onChange={(e) => setTaskEnd(e.target.value)} /></div>
                </div>
                <div className="form-group">
                  <label>WBS Item</label>
                  <select value={taskWbs} onChange={(e) => setTaskWbs(e.target.value)}>
                    <option value="">— none —</option>
                    {wbsItems.map((w) => <option key={w.id} value={w.id}>{w.wbsCode} {w.name}</option>)}
                  </select>
                </div>
                <div className="form-actions"><button type="submit">Add</button></div>
              </form>
            </div>
          )}
          <div className="card">
            <DataTable
              columns={[
                { key: 'name', label: 'Name' },
                { key: 'status', label: 'Status', render: (v, row) => (
                  <select
                    value={v as string}
                    className={`badge ${STATUS_BADGE[v as string] ?? 'badge-gray'}`}
                    style={{ border: 'none', cursor: 'pointer', fontSize: 11, padding: '2px 6px' }}
                    onChange={(e) => updateTaskStatus(row.id as string, e.target.value)}
                  >
                    {TASK_STATUSES.map((s) => <option key={s}>{s}</option>)}
                  </select>
                )},
                { key: 'startDate', label: 'Start', render: (v) => v ? new Date(v as string).toLocaleDateString() : '—' },
                { key: 'endDate', label: 'End', render: (v) => v ? new Date(v as string).toLocaleDateString() : '—' },
              ]}
              rows={tasks as unknown as Record<string, unknown>[]}
              emptyText="No tasks"
            />
          </div>
        </>
      )}
    </div>
  )
}
