import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { apiGet, ApiError } from '../../api'
import { getSub, getRoles } from '../../keycloak'
import ErrorBanner from '../../components/ErrorBanner'
import Charter from './modules/Charter'
import WbsTasks from './modules/WbsTasks'
import CostItems from './modules/CostItems'
import Baselines from './modules/Baselines'
import Deliverables from './modules/Deliverables'
import ChangeRequests from './modules/ChangeRequests'
import DecisionLog from './modules/DecisionLog'
import StatusReports from './modules/StatusReports'
import Closing from './modules/Closing'

export interface Project {
  id: string; name: string; status: string; pmId: string; sponsorId: string
  startTarget: string | null; endTarget: string | null; createdAt: string
}

export interface RoleAssignment { id: string; projectId: string; userId: string; role: string }

export type ProjectRole = 'PM' | 'SPONSOR' | 'TEAM_MEMBER' | 'STAKEHOLDER' | 'QA' | 'FINANCE' | 'PROCUREMENT'

const MODULES = [
  { key: 'charter', label: 'Charter' },
  { key: 'wbs-tasks', label: 'WBS & Tasks' },
  { key: 'cost-items', label: 'Cost Items' },
  { key: 'baselines', label: 'Baselines' },
  { key: 'deliverables', label: 'Deliverables' },
  { key: 'change-requests', label: 'Change Requests' },
  { key: 'decision-log', label: 'Decision Log' },
  { key: 'status-reports', label: 'Status Reports' },
  { key: 'closing', label: 'Closing' },
]

export default function ProjectWorkspace() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [project, setProject] = useState<Project | null>(null)
  const [members, setMembers] = useState<RoleAssignment[]>([])
  const [error, setError] = useState<string | null>(null)
  const [activeModule, setActiveModule] = useState('charter')

  async function loadProject() {
    try {
      const [p, m] = await Promise.all([
        apiGet<Project>(`/api/projects/${id}`),
        apiGet<RoleAssignment[]>(`/api/projects/${id}/members`),
      ])
      setProject(p)
      setMembers(m)
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to load project') }
  }

  useEffect(() => { loadProject() }, [id])

  // Determine caller's project role
  const sub = getSub()
  const globalRoles = getRoles()
  const isAdmin = globalRoles.includes('crm_admin')
  const myAssignment = members.find((m) => m.userId === sub)
  const myRole = isAdmin ? 'PM' : (myAssignment?.role as ProjectRole | undefined)

  const isPM = isAdmin || myRole === 'PM'
  const isSponsor = isAdmin || myRole === 'SPONSOR'
  const isQA = isAdmin || myRole === 'QA'

  function renderModule() {
    if (!project) return null
    const ctx = { projectId: id!, project, myRole: myRole ?? 'STAKEHOLDER', isPM, isSponsor, isQA, onRefresh: loadProject }
    switch (activeModule) {
      case 'charter': return <Charter {...ctx} />
      case 'wbs-tasks': return <WbsTasks {...ctx} />
      case 'cost-items': return <CostItems {...ctx} />
      case 'baselines': return <Baselines {...ctx} />
      case 'deliverables': return <Deliverables {...ctx} />
      case 'change-requests': return <ChangeRequests {...ctx} />
      case 'decision-log': return <DecisionLog {...ctx} />
      case 'status-reports': return <StatusReports {...ctx} />
      case 'closing': return <Closing {...ctx} />
      default: return null
    }
  }

  if (!project) return (
    <div className="page">
      {error ? <ErrorBanner message={error} onDismiss={() => setError(null)} /> : <div className="empty">Loading…</div>}
    </div>
  )

  return (
    <div className="workspace">
      <aside className="workspace-sidebar">
        <button
          className="sidebar-link"
          style={{ color: 'var(--text-muted)', fontSize: 12, marginBottom: 4 }}
          onClick={() => navigate('/projects')}
        >
          ← Projects
        </button>
        <div style={{ padding: '0 16px 8px', fontWeight: 700, fontSize: 13, color: 'var(--text)' }}>{project.name}</div>
        <div style={{ padding: '0 16px 12px', display: 'flex', gap: 4 }}>
          <span className={`badge ${project.status === 'ACTIVE' ? 'badge-green' : project.status === 'CLOSED' ? 'badge-blue' : 'badge-gray'}`} style={{ fontSize: 10 }}>
            {project.status}
          </span>
          {myRole && <span className="badge badge-blue" style={{ fontSize: 10 }}>{myRole}</span>}
        </div>
        <h3>Modules</h3>
        {MODULES.map((m) => (
          <button
            key={m.key}
            className={`sidebar-link ${activeModule === m.key ? 'active' : ''}`}
            onClick={() => setActiveModule(m.key)}
          >
            {m.label}
          </button>
        ))}
      </aside>
      <div className="workspace-content">
        {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}
        {renderModule()}
      </div>
    </div>
  )
}
