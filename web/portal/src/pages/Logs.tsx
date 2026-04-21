import { useEffect, useState } from 'react'
import { format } from 'date-fns'
import { api, LogEntry, LogPage } from '../lib/api'

const EVENT_COLORS: Record<string, string> = {
  UNLOCK: 'text-green-600',
  DENY:   'text-red-500',
  REVOKE: 'text-yellow-600',
}

export default function Logs() {
  const [data, setData]   = useState<LogPage | null>(null)
  const [page, setPage]   = useState(1)

  useEffect(() => {
    api.listLogs(page).then(setData)
  }, [page])

  if (!data) return <p className="text-gray-400">Loading…</p>

  const totalPages = Math.ceil(data.total / data.pageSize)

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Audit Log</h1>
      <div className="bg-white rounded-xl shadow overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-500 text-xs uppercase">
            <tr>
              <th className="px-4 py-3 text-left">Time</th>
              <th className="px-4 py-3 text-left">Event</th>
              <th className="px-4 py-3 text-left">Key</th>
              <th className="px-4 py-3 text-left">Device</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {data.items.map((entry: LogEntry) => (
              <tr key={entry.id}>
                <td className="px-4 py-3 text-gray-500 whitespace-nowrap">
                  {format(new Date(entry.occurredAt), 'MMM d, HH:mm:ss')}
                </td>
                <td className={`px-4 py-3 font-semibold ${EVENT_COLORS[entry.event] ?? 'text-gray-700'}`}>
                  {entry.event}
                </td>
                <td className="px-4 py-3 text-gray-700">{entry.keyLabel ?? '—'}</td>
                <td className="px-4 py-3 text-gray-500">{entry.deviceLabel ?? '—'}</td>
              </tr>
            ))}
            {data.items.length === 0 && (
              <tr><td colSpan={4} className="px-4 py-8 text-center text-gray-400">No events yet</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {totalPages > 1 && (
        <div className="flex items-center gap-2 justify-end text-sm">
          <button
            onClick={() => setPage(p => Math.max(1, p - 1))}
            disabled={page === 1}
            className="px-3 py-1 border rounded disabled:opacity-40"
          >Prev</button>
          <span className="text-gray-500">{page} / {totalPages}</span>
          <button
            onClick={() => setPage(p => Math.min(totalPages, p + 1))}
            disabled={page === totalPages}
            className="px-3 py-1 border rounded disabled:opacity-40"
          >Next</button>
        </div>
      )}
    </div>
  )
}
