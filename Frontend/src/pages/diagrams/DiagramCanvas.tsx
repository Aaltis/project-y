import { useCallback, useEffect, useRef, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import ReactFlow, {
  addEdge,
  applyEdgeChanges,
  applyNodeChanges,
  Background,
  Controls,
  type Connection,
  type Edge,
  type EdgeChange,
  type Node,
  type NodeChange,
  type NodeTypes,
} from 'reactflow'
import 'reactflow/dist/style.css'
import { apiGet, apiPost, apiPut, apiDelete, ApiError } from '../../api'
import ErrorBanner from '../../components/ErrorBanner'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
interface DiagramMeta {
  id: string
  name: string
  ownerId: string
}

interface NodeData {
  nodeKey: string
  entityType?: string
  entityId?: string
  label?: string
  color?: string
  shape?: string
}

interface EdgeData {
  sourceKey: string
  targetKey: string
  label?: string
  style?: string
}

interface DiagramDetail {
  diagram: DiagramMeta
  nodes: (NodeData & { id: string; x: number; y: number })[]
  edges: (EdgeData & { id: string })[]
}

// Entity type → color mapping
const ENTITY_COLORS: Record<string, string> = {
  ACCOUNT: '#3b82f6',
  CONTACT: '#8b5cf6',
  OPPORTUNITY: '#10b981',
  PROJECT: '#f59e0b',
  TASK: '#6b7280',
  RISK: '#ef4444',
  NOTE: '#fbbf24',
}

// ---------------------------------------------------------------------------
// Custom node: EntityNode
// ---------------------------------------------------------------------------
function EntityNode({ data }: { data: NodeData }) {
  const color = data.color ?? ENTITY_COLORS[data.entityType ?? ''] ?? '#6b7280'
  return (
    <div style={{
      border: `2px solid ${color}`,
      borderRadius: 8,
      background: '#fff',
      minWidth: 120,
      maxWidth: 200,
      boxShadow: '0 1px 4px rgba(0,0,0,0.15)',
    }}>
      {data.entityType && (
        <div style={{
          background: color,
          color: '#fff',
          fontSize: 10,
          fontWeight: 700,
          padding: '2px 8px',
          borderRadius: '6px 6px 0 0',
          textTransform: 'uppercase',
          letterSpacing: 0.5,
        }}>
          {data.entityType}
        </div>
      )}
      <div style={{ padding: '6px 10px', fontSize: 13, fontWeight: 500 }}>
        {data.label ?? data.nodeKey}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Custom node: NoteNode (editable sticky)
// ---------------------------------------------------------------------------
function NoteNode({ data, id }: { data: NodeData; id: string }) {
  const [text, setText] = useState(data.label ?? '')
  return (
    <div
      style={{
        background: '#fef9c3',
        border: '1px solid #fde047',
        borderRadius: 4,
        padding: 8,
        minWidth: 140,
        maxWidth: 220,
        boxShadow: '2px 2px 6px rgba(0,0,0,0.1)',
      }}
    >
      <textarea
        value={text}
        onChange={(e) => {
          setText(e.target.value)
          data.label = e.target.value   // mutate for save
        }}
        style={{
          width: '100%',
          minHeight: 60,
          border: 'none',
          background: 'transparent',
          resize: 'both',
          fontFamily: 'inherit',
          fontSize: 12,
          outline: 'none',
        }}
        placeholder="Note…"
      />
    </div>
  )
}

const nodeTypes: NodeTypes = {
  entity: EntityNode,
  note: NoteNode,
}

// ---------------------------------------------------------------------------
// Search types for entity sidebar
// ---------------------------------------------------------------------------
const SEARCH_TYPES = [
  { value: 'ACCOUNT', label: 'Account', path: '/api/accounts?search={q}&page=0&size=10' },
  { value: 'CONTACT', label: 'Contact', path: '/api/accounts' },   // not searchable by name — show all
  { value: 'OPPORTUNITY', label: 'Opportunity', path: '/api/opportunities?mine=false&page=0&size=10' },
  { value: 'PROJECT', label: 'Project', path: '/api/projects' },
]

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------
export default function DiagramCanvas() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()

  const [diagram, setDiagram] = useState<DiagramMeta | null>(null)
  const [nodes, setNodes] = useState<Node[]>([])
  const [edges, setEdges] = useState<Edge[]>([])
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(true)

  // Sidebar state
  const [searchType, setSearchType] = useState('ACCOUNT')
  const [searchQuery, setSearchQuery] = useState('')
  const [searchResults, setSearchResults] = useState<{ id: string; name: string }[]>([])
  const [searching, setSearching] = useState(false)

  // Debounce timer for auto-save
  const autoSaveTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  // -------------------------------------------------------------------------
  // Load diagram on mount
  // -------------------------------------------------------------------------
  useEffect(() => {
    if (!id) return
    apiGet<DiagramDetail>(`/api/diagrams/${id}`).then((d) => {
      setDiagram(d.diagram)
      setNodes(d.nodes.map((n) => ({
        id: n.id,
        type: n.entityType === 'NOTE' || !n.entityType ? 'note' : 'entity',
        position: { x: n.x, y: n.y },
        data: {
          nodeKey: n.nodeKey,
          entityType: n.entityType,
          entityId: n.entityId,
          label: n.label,
          color: n.color ?? ENTITY_COLORS[n.entityType ?? ''],
        },
      })))
      setEdges(d.edges.map((e) => ({
        id: e.id,
        source: e.sourceKey,
        target: e.targetKey,
        label: e.label,
      })))
    }).catch((e) => {
      setError(e instanceof ApiError ? e.message : 'Failed to load diagram')
    })
  }, [id])

  // -------------------------------------------------------------------------
  // ReactFlow handlers
  // -------------------------------------------------------------------------
  const onNodesChange = useCallback((changes: NodeChange[]) => {
    setNodes((nds) => applyNodeChanges(changes, nds))
    markDirty()
  }, [])

  const onEdgesChange = useCallback((changes: EdgeChange[]) => {
    setEdges((eds) => applyEdgeChanges(changes, eds))
    markDirty()
  }, [])

  const onConnect = useCallback((connection: Connection) => {
    setEdges((eds) => addEdge(connection, eds))
    markDirty()
  }, [])

  function markDirty() {
    setSaved(false)
    if (autoSaveTimer.current) clearTimeout(autoSaveTimer.current)
    autoSaveTimer.current = setTimeout(() => doSave(), 2000)
  }

  // -------------------------------------------------------------------------
  // Save canvas
  // -------------------------------------------------------------------------
  async function doSave() {
    if (!id) return
    try {
      const payload = {
        nodes: nodes.map((n) => ({
          nodeKey: (n.data as NodeData).nodeKey ?? n.id,
          entityType: (n.data as NodeData).entityType ?? null,
          entityId: (n.data as NodeData).entityId ?? null,
          label: (n.data as NodeData).label ?? null,
          x: n.position.x,
          y: n.position.y,
          color: (n.data as NodeData).color ?? null,
          shape: n.type === 'note' ? 'NOTE' : 'RECTANGLE',
        })),
        edges: edges.map((e) => ({
          sourceKey: e.source,
          targetKey: e.target,
          label: e.label ?? null,
          style: 'SOLID',
        })),
      }
      await apiPut(`/api/diagrams/${id}/canvas`, payload)
      setSaved(true)
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Save failed')
    }
  }

  // -------------------------------------------------------------------------
  // Add node from sidebar drag/click
  // -------------------------------------------------------------------------
  function addEntityNode(entityType: string, entityId: string, label: string) {
    const nodeKey = `${entityType.toLowerCase()}-${entityId}`
    const newNode: Node = {
      id: nodeKey,
      type: 'entity',
      position: { x: 100 + Math.random() * 200, y: 100 + Math.random() * 200 },
      data: {
        nodeKey,
        entityType,
        entityId,
        label,
        color: ENTITY_COLORS[entityType] ?? '#6b7280',
      },
    }
    setNodes((nds) => [...nds, newNode])
    markDirty()
  }

  function addNoteNode() {
    const nodeKey = `note-${Date.now()}`
    const newNode: Node = {
      id: nodeKey,
      type: 'note',
      position: { x: 200, y: 200 },
      data: { nodeKey, entityType: 'NOTE', label: '' },
    }
    setNodes((nds) => [...nds, newNode])
    markDirty()
  }

  // -------------------------------------------------------------------------
  // Entity search
  // -------------------------------------------------------------------------
  async function runSearch() {
    const typeInfo = SEARCH_TYPES.find((t) => t.value === searchType)
    if (!typeInfo) return
    setSearching(true)
    setSearchResults([])
    try {
      const url = typeInfo.path.replace('{q}', encodeURIComponent(searchQuery))
      const raw = await apiGet<unknown>(url)
      let items: { id: string; name: string }[] = []
      if (Array.isArray(raw)) {
        items = raw.map((r: Record<string, unknown>) => ({ id: r.id as string, name: (r.name ?? r.email ?? r.id) as string }))
      } else if (raw && typeof raw === 'object' && 'content' in raw) {
        items = (raw as { content: Record<string, unknown>[] }).content.map((r) => ({ id: r.id as string, name: (r.name ?? r.id) as string }))
      }
      setSearchResults(items.slice(0, 10))
    } catch {
      setSearchResults([])
    } finally {
      setSearching(false)
    }
  }

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------
  if (!diagram) {
    return <div className="page"><div className="empty">Loading diagram…</div></div>
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: 'calc(100vh - var(--nav-h))' }}>
      {/* Toolbar */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        padding: '6px 16px',
        borderBottom: '1px solid var(--border)',
        background: 'var(--surface)',
        flexShrink: 0,
      }}>
        <button className="btn btn-secondary btn-sm" onClick={() => navigate('/diagrams')}>
          ← Diagrams
        </button>
        <span style={{ fontWeight: 600, fontSize: 14 }}>{diagram.name}</span>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 8, alignItems: 'center' }}>
          <span style={{ fontSize: 12, color: saved ? 'var(--success)' : 'var(--warning)' }}>
            {saved ? 'Saved' : 'Unsaved changes'}
          </span>
          <button className="btn btn-sm" onClick={doSave}>Save</button>
          <button className="btn btn-secondary btn-sm" onClick={addNoteNode}>+ Note</button>
        </div>
      </div>

      {error && (
        <div style={{ padding: '0 16px', paddingTop: 8 }}>
          <ErrorBanner message={error} onDismiss={() => setError(null)} />
        </div>
      )}

      {/* Canvas + sidebar */}
      <div style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
        {/* Entity search sidebar */}
        <div style={{
          width: 240,
          borderRight: '1px solid var(--border)',
          padding: 12,
          display: 'flex',
          flexDirection: 'column',
          gap: 8,
          background: 'var(--surface)',
          overflowY: 'auto',
          flexShrink: 0,
        }}>
          <div style={{ fontWeight: 600, fontSize: 13 }}>Add Entity</div>

          <select
            value={searchType}
            onChange={(e) => { setSearchType(e.target.value); setSearchResults([]) }}
            style={{ fontSize: 12, padding: '4px 6px', borderRadius: 4, border: '1px solid var(--border)' }}
          >
            {SEARCH_TYPES.map((t) => (
              <option key={t.value} value={t.value}>{t.label}</option>
            ))}
          </select>

          <div style={{ display: 'flex', gap: 4 }}>
            <input
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && runSearch()}
              placeholder="Search…"
              style={{ fontSize: 12, padding: '4px 6px', borderRadius: 4, border: '1px solid var(--border)', flex: 1 }}
            />
            <button className="btn btn-sm" onClick={runSearch} disabled={searching} style={{ fontSize: 11 }}>
              Go
            </button>
          </div>

          {searching && <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Searching…</div>}

          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            {searchResults.map((r) => (
              <button
                key={r.id}
                onClick={() => addEntityNode(searchType, r.id, r.name)}
                style={{
                  textAlign: 'left',
                  padding: '5px 8px',
                  borderRadius: 4,
                  border: `1px solid ${ENTITY_COLORS[searchType] ?? '#6b7280'}`,
                  background: '#fff',
                  fontSize: 12,
                  cursor: 'pointer',
                  color: 'var(--text)',
                }}
              >
                <span style={{
                  display: 'inline-block',
                  width: 8,
                  height: 8,
                  borderRadius: '50%',
                  background: ENTITY_COLORS[searchType] ?? '#6b7280',
                  marginRight: 6,
                }} />
                {r.name}
              </button>
            ))}
          </div>
        </div>

        {/* React Flow canvas */}
        <div style={{ flex: 1 }}>
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onConnect={onConnect}
            nodeTypes={nodeTypes}
            fitView
            deleteKeyCode="Delete"
          >
            <Background />
            <Controls />
          </ReactFlow>
        </div>
      </div>
    </div>
  )
}
