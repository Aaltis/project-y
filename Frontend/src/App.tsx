import { Routes, Route, Navigate } from 'react-router-dom'
import Layout from './components/Layout'
import Dashboard from './pages/Dashboard'
import AccountsList from './pages/crm/AccountsList'
import AccountDetail from './pages/crm/AccountDetail'
import OpportunitiesList from './pages/crm/OpportunitiesList'
import OpportunityDetail from './pages/crm/OpportunityDetail'
import ProjectsList from './pages/projects/ProjectsList'
import ProjectWorkspace from './pages/projects/ProjectWorkspace'

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Dashboard />} />
        <Route path="crm/accounts" element={<AccountsList />} />
        <Route path="crm/accounts/:id" element={<AccountDetail />} />
        <Route path="crm/opportunities" element={<OpportunitiesList />} />
        <Route path="crm/opportunities/:id" element={<OpportunityDetail />} />
        <Route path="projects" element={<ProjectsList />} />
        <Route path="projects/:id" element={<ProjectWorkspace />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}
