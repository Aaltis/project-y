interface Props {
  message: string
  onDismiss?: () => void
}

export default function ErrorBanner({ message, onDismiss }: Props) {
  return (
    <div style={{
      background: 'var(--error-bg)',
      border: '1px solid #fca5a5',
      borderRadius: 'var(--radius)',
      padding: '10px 14px',
      display: 'flex',
      alignItems: 'flex-start',
      gap: 10,
      marginBottom: 16,
      color: 'var(--error)',
      fontSize: 13,
    }}>
      <span style={{ flex: 1 }}>{message}</span>
      {onDismiss && (
        <button
          onClick={onDismiss}
          style={{ background: 'none', color: 'var(--error)', border: 'none', padding: 0, cursor: 'pointer', fontSize: 16, lineHeight: 1 }}
        >
          ×
        </button>
      )}
    </div>
  )
}
