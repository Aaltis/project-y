import { NavLink, Outlet } from 'react-router-dom'
import { getUsername, logout } from '../keycloak'

const NAV_LINKS = [
  { to: '/', label: 'Dashboard', end: true },
  { to: '/crm/accounts', label: 'Accounts' },
  { to: '/crm/opportunities', label: 'Opportunities' },
  { to: '/projects', label: 'Projects' },
  { to: '/diagrams', label: 'Diagrams' },
]

export default function Layout() {
  return (
    <>
      <nav style={{
        height: 'var(--nav-h)',
        background: '#1e293b',
        display: 'flex',
        alignItems: 'center',
        padding: '0 20px',
        gap: 4,
        position: 'sticky',
        top: 0,
        zIndex: 50,
      }}>
        <span style={{ color: '#fff', fontWeight: 700, fontSize: 15, marginRight: 20 }}>
          Project Y
        </span>
        {NAV_LINKS.map(({ to, label, end }) => (
          <NavLink
            key={to}
            to={to}
            end={end}
            style={({ isActive }) => ({
              padding: '5px 12px',
              borderRadius: 'var(--radius)',
              color: isActive ? '#fff' : '#94a3b8',
              fontWeight: isActive ? 600 : 400,
              fontSize: 13,
              textDecoration: 'none',
              background: isActive ? 'rgba(255,255,255,0.1)' : 'none',
            })}
          >
            {label}
          </NavLink>
        ))}
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 12 }}>
          <span style={{ color: '#94a3b8', fontSize: 13 }}>{getUsername()}</span>
          <button
            className="btn-secondary btn-sm"
            onClick={logout}
            style={{ background: 'transparent', color: '#94a3b8', borderColor: '#475569' }}
          >
            Logout
          </button>
        </div>
      </nav>
      <Outlet />
    </>
  )
}
