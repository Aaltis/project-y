import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { apiGet, apiPost, apiPut, apiDelete, ApiError } from '../../api'
import DataTable from '../../components/DataTable'
import ErrorBanner from '../../components/ErrorBanner'

interface Account { id: string; name: string; ownerId: string; createdAt: string }
interface Contact { id: string; name: string; email: string; phone: string }
interface Opportunity { id: string; name: string; stage: string; amount: number | null; closeDate: string | null }

export default function AccountDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [account, setAccount] = useState<Account | null>(null)
  const [contacts, setContacts] = useState<Contact[]>([])
  const [opportunities, setOpportunities] = useState<Opportunity[]>([])
  const [tab, setTab] = useState<'contacts' | 'opportunities'>('contacts')
  const [error, setError] = useState<string | null>(null)

  // Contact create form
  const [showContactForm, setShowContactForm] = useState(false)
  const [cName, setCName] = useState(''); const [cEmail, setCEmail] = useState(''); const [cPhone, setCPhone] = useState('')

  // Contact edit form
  const [editingContactId, setEditingContactId] = useState<string | null>(null)
  const [ecName, setEcName] = useState(''); const [ecEmail, setEcEmail] = useState(''); const [ecPhone, setEcPhone] = useState('')

  // Opportunity form
  const [showOppForm, setShowOppForm] = useState(false)
  const [oName, setOName] = useState('')

  async function loadAll() {
    try {
      const [acc, ctcts, opps] = await Promise.all([
        apiGet<Account>(`/api/accounts/${id}`),
        apiGet<Contact[]>(`/api/accounts/${id}/contacts`),
        apiGet<Opportunity[]>(`/api/opportunities?accountId=${id}&page=0&size=50`),
      ])
      setAccount(acc)
      setContacts(ctcts)
      setOpportunities(Array.isArray(opps) ? opps : (opps as { content: Opportunity[] }).content ?? [])
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Failed to load')
    }
  }

  useEffect(() => { loadAll() }, [id])

  async function createContact(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/accounts/${id}/contacts`, { name: cName, email: cEmail, phone: cPhone })
      setCName(''); setCEmail(''); setCPhone('')
      setShowContactForm(false)
      loadAll()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  function startEditContact(contact: Contact) {
    setEditingContactId(contact.id)
    setEcName(contact.name)
    setEcEmail(contact.email)
    setEcPhone(contact.phone)
  }

  async function saveEditContact(e: React.FormEvent) {
    e.preventDefault()
    if (!editingContactId) return
    try {
      await apiPut(`/api/accounts/${id}/contacts/${editingContactId}`, { name: ecName, email: ecEmail, phone: ecPhone })
      setEditingContactId(null)
      loadAll()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to save') }
  }

  async function deleteContact(contactId: string) {
    if (!confirm('Delete this contact?')) return
    try {
      await apiDelete(`/api/accounts/${id}/contacts/${contactId}`)
      loadAll()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed to delete') }
  }

  async function createOpportunity(e: React.FormEvent) {
    e.preventDefault()
    try {
      await apiPost(`/api/opportunities`, { name: oName, accountId: id })
      setOName('')
      setShowOppForm(false)
      loadAll()
    } catch (e) { setError(e instanceof ApiError ? e.message : 'Failed') }
  }

  if (!account) return <div className="page"><div className="empty">Loading…</div></div>

  return (
    <div className="page">
      <div className="page-header">
        <div>
          <button className="btn btn-secondary btn-sm" style={{ marginBottom: 8 }} onClick={() => navigate('/crm/accounts')}>← Accounts</button>
          <h1 className="page-title">{account.name}</h1>
          <span style={{ color: 'var(--text-muted)', fontSize: 12 }}>ID: {account.id}</span>
        </div>
      </div>

      {error && <ErrorBanner message={error} onDismiss={() => setError(null)} />}

      <div className="tabs">
        <button className={`tab-btn ${tab === 'contacts' ? 'active' : ''}`} onClick={() => setTab('contacts')}>
          Contacts ({contacts.length})
        </button>
        <button className={`tab-btn ${tab === 'opportunities' ? 'active' : ''}`} onClick={() => setTab('opportunities')}>
          Opportunities ({opportunities.length})
        </button>
      </div>

      {tab === 'contacts' && (
        <>
          <div style={{ marginBottom: 12 }}>
            <button className="btn-secondary btn btn-sm" onClick={() => setShowContactForm((v) => !v)}>
              {showContactForm ? 'Cancel' : '+ Add Contact'}
            </button>
          </div>
          {showContactForm && (
            <div className="card">
              <form onSubmit={createContact}>
                <div className="form-row">
                  <div className="form-group"><label>Name</label><input value={cName} onChange={(e) => setCName(e.target.value)} required /></div>
                  <div className="form-group"><label>Email</label><input type="email" value={cEmail} onChange={(e) => setCEmail(e.target.value)} /></div>
                  <div className="form-group"><label>Phone</label><input value={cPhone} onChange={(e) => setCPhone(e.target.value)} /></div>
                </div>
                <div className="form-actions">
                  <button type="submit">Add</button>
                </div>
              </form>
            </div>
          )}
          {editingContactId && (
            <div className="card">
              <form onSubmit={saveEditContact}>
                <div className="form-row">
                  <div className="form-group"><label>Name</label><input value={ecName} onChange={(e) => setEcName(e.target.value)} required /></div>
                  <div className="form-group"><label>Email</label><input type="email" value={ecEmail} onChange={(e) => setEcEmail(e.target.value)} /></div>
                  <div className="form-group"><label>Phone</label><input value={ecPhone} onChange={(e) => setEcPhone(e.target.value)} /></div>
                </div>
                <div className="form-actions">
                  <button type="submit">Save</button>
                  <button type="button" className="btn btn-secondary" onClick={() => setEditingContactId(null)}>Cancel</button>
                </div>
              </form>
            </div>
          )}
          <div className="card">
            <DataTable
              columns={[
                { key: 'name', label: 'Name' },
                { key: 'email', label: 'Email' },
                { key: 'phone', label: 'Phone' },
                {
                  key: 'id', label: '',
                  render: (_, row) => (
                    <div style={{ display: 'flex', gap: 4 }} onClick={(e) => e.stopPropagation()}>
                      <button className="btn btn-secondary btn-sm" onClick={() => startEditContact(row as unknown as Contact)}>Edit</button>
                      <button className="btn btn-danger btn-sm" onClick={() => deleteContact(row.id as string)}>Delete</button>
                    </div>
                  ),
                },
              ]}
              rows={contacts as unknown as Record<string, unknown>[]}
              emptyText="No contacts"
            />
          </div>
        </>
      )}

      {tab === 'opportunities' && (
        <>
          <div style={{ marginBottom: 12 }}>
            <button className="btn-secondary btn btn-sm" onClick={() => setShowOppForm((v) => !v)}>
              {showOppForm ? 'Cancel' : '+ Add Opportunity'}
            </button>
          </div>
          {showOppForm && (
            <div className="card">
              <form onSubmit={createOpportunity}>
                <div className="form-group"><label>Opportunity Name</label><input value={oName} onChange={(e) => setOName(e.target.value)} required /></div>
                <div className="form-actions"><button type="submit">Create</button></div>
              </form>
            </div>
          )}
          <div className="card">
            <DataTable
              columns={[
                { key: 'name', label: 'Name' },
                { key: 'stage', label: 'Stage', render: (v) => <span className="badge badge-blue">{v as string}</span> },
                { key: 'amount', label: 'Amount', render: (v) => v ? `€${(v as number).toLocaleString()}` : '—' },
                { key: 'closeDate', label: 'Close Date', render: (v) => v ? new Date(v as string).toLocaleDateString() : '—' },
              ]}
              rows={opportunities as unknown as Record<string, unknown>[]}
              onRowClick={(row) => navigate(`/crm/opportunities/${row.id}`)}
              emptyText="No opportunities"
            />
          </div>
        </>
      )}
    </div>
  )
}
