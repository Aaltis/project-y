import React, { useEffect, useState } from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import { initKeycloak } from './keycloak'
import './index.css'

function Root() {
  const [ready, setReady] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    initKeycloak()
      .then(() => setReady(true))
      .catch((e) => setError(String(e)))
  }, [])

  if (error) return <div className="auth-error">Authentication error: {error}</div>
  if (!ready) return <div className="auth-loading">Authenticating…</div>

  return (
    <BrowserRouter>
      <App />
    </BrowserRouter>
  )
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>,
)
