import Keycloak from 'keycloak-js'

const keycloak = new Keycloak({
  url: import.meta.env.VITE_KEYCLOAK_URL as string,
  realm: import.meta.env.VITE_KEYCLOAK_REALM as string,
  clientId: import.meta.env.VITE_KEYCLOAK_CLIENT_ID as string,
})

let initPromise: Promise<void> | null = null

export function initKeycloak(): Promise<void> {
  if (!initPromise) {
    initPromise = keycloak.init({ onLoad: 'login-required', pkceMethod: 'S256', checkLoginIframe: false }).then(() => {})
  }
  return initPromise
}

export async function getToken(): Promise<string> {
  await keycloak.updateToken(30)
  return keycloak.token!
}

export function getUsername(): string {
  return (keycloak.tokenParsed?.preferred_username as string) ?? keycloak.subject ?? ''
}

export function getSub(): string {
  return keycloak.subject ?? ''
}

export function getRoles(): string[] {
  return (keycloak.tokenParsed?.realm_access as { roles: string[] })?.roles ?? []
}

export function logout(): void {
  keycloak.logout()
}
