interface Column {
  key: string
  label: string
  render?: (value: unknown, row: Record<string, unknown>) => React.ReactNode
}

interface Props {
  columns: Column[]
  rows: Record<string, unknown>[]
  onRowClick?: (row: Record<string, unknown>) => void
  emptyText?: string
}

import React from 'react'

export default function DataTable({ columns, rows, onRowClick, emptyText = 'No records' }: Props) {
  if (rows.length === 0) {
    return <div className="empty">{emptyText}</div>
  }

  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((c) => <th key={c.key}>{c.label}</th>)}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr
              key={i}
              className={onRowClick ? 'clickable' : ''}
              onClick={onRowClick ? () => onRowClick(row) : undefined}
            >
              {columns.map((c) => (
                <td key={c.key}>
                  {c.render ? c.render(row[c.key], row) : String(row[c.key] ?? '')}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
