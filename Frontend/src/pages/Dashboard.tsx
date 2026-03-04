import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getUsername, getSub, getRoles } from '../keycloak'

interface HealthStatus {
  status: 'UP' | 'DOWN' | 'unknown'
}

export default function Dashboard() {
  const [health, setHealth] = useState<HealthStatus>({ status: 'unknown' })

  useEffect(() => {
    fetch('/actuator/health')
      .then((r) => r.json())
      .then((d) => setHealth({ status: d.status === 'UP' ? 'UP' : 'DOWN' }))
      .catch(() => setHealth({ status: 'DOWN' }))
  }, [])

  const roles = getRoles()

  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Dashboard</h1>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        {/* System status */}
        <div className="card">
          <div className="card-title">System Status</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span
              className="status-dot"
              style={{
                background: health.status === 'UP' ? 'var(--success)' : health.status === 'DOWN' ? 'var(--error)' : 'var(--warning)',
              }}
            />
            <span style={{ fontWeight: 600 }}>
              Gateway&nbsp;
              <span style={{ color: health.status === 'UP' ? 'var(--success)' : health.status === 'unknown' ? 'var(--warning)' : 'var(--error)' }}>
                {health.status}
              </span>
            </span>
          </div>
          <p style={{ marginTop: 8, fontSize: 12, color: 'var(--text-muted)' }}>
            All API traffic routes through the Gateway on port 8080.
          </p>
        </div>

        {/* Token info */}
        <div className="card">
          <div className="card-title">Current Session</div>
          <table style={{ fontSize: 13 }}>
            <tbody>
              <tr>
                <td style={{ paddingRight: 12, color: 'var(--text-muted)', paddingBottom: 6 }}>Username</td>
                <td><strong>{getUsername()}</strong></td>
              </tr>
              <tr>
                <td style={{ color: 'var(--text-muted)', paddingBottom: 6 }}>Subject (sub)</td>
                <td style={{ fontFamily: 'monospace', fontSize: 11 }}>{getSub()}</td>
              </tr>
              <tr>
                <td style={{ color: 'var(--text-muted)' }}>Realm roles</td>
                <td>
                  {roles.map((r) => (
                    <span key={r} className="badge badge-blue" style={{ marginRight: 4 }}>{r}</span>
                  ))}
                  {roles.length === 0 && <span className="badge badge-gray">none</span>}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      {/* Quick links */}
      <div className="card">
        <div className="card-title">Quick Links</div>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
          <Link to="/crm/accounts" className="btn btn-secondary">CRM Accounts</Link>
          <Link to="/crm/opportunities" className="btn btn-secondary">Opportunities</Link>
          <Link to="/projects" className="btn btn-secondary">Projects</Link>
        </div>
      </div>
    </div>
  )
}
