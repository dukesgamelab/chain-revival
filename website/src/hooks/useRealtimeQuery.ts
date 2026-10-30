import { useEffect, useState, useCallback, useRef } from 'react'
import { supabase } from '../lib/supabase'
import type { RealtimeChannel } from '@supabase/supabase-js'

interface UseRealtimeQueryOptions<T> {
  table: string
  select: string
  filter?: { column: string; operator: string; value: string | number }
  order?: { column: string; ascending?: boolean }
  secondaryOrder?: { column: string; ascending?: boolean }
  limit?: number
  enabled?: boolean
  onInsert?: (row: T) => void
}

export function useRealtimeQuery<T extends Record<string, unknown>>(opts: UseRealtimeQueryOptions<T>) {
  const { table, select, filter, order, secondaryOrder, limit, enabled = true, onInsert } = opts
  const [data, setData] = useState<T[]>([])
  const [loading, setLoading] = useState(true)
  const channelRef = useRef<RealtimeChannel | null>(null)

  const fetchData = useCallback(async () => {
    let query = supabase.from(table).select(select)
    if (filter) query = query.filter(filter.column, filter.operator, filter.value)
    if (order) query = query.order(order.column, { ascending: order.ascending ?? false })
    if (secondaryOrder) query = query.order(secondaryOrder.column, { ascending: secondaryOrder.ascending ?? true })
    if (limit) query = query.limit(limit)

    const { data: rows } = await query
    if (rows) setData(rows as unknown as T[])
    setLoading(false)
  }, [table, select, filter?.column, filter?.operator, filter?.value, order?.column, order?.ascending, secondaryOrder?.column, secondaryOrder?.ascending, limit])

  useEffect(() => {
    if (!enabled) {
      setLoading(false)
      return
    }

    fetchData()

    const channelName = `${table}-${filter?.value ?? 'all'}-${Math.random().toString(36).slice(2)}`
    const channelConfig: Record<string, unknown> = {
      event: '*',
      schema: 'public',
      table,
    }
    if (filter) {
      channelConfig.filter = `${filter.column}=${filter.operator}.${filter.value}`
    }

    const channel = supabase
      .channel(channelName)
      .on('postgres_changes', channelConfig as never, (payload) => {
        if (payload.eventType === 'INSERT') {
          const newRow = payload.new as T
          if (onInsert) {
            onInsert(newRow)
          } else {
            setData(prev => [newRow, ...prev].slice(0, limit ?? 1000))
          }
        } else if (payload.eventType === 'UPDATE') {
          setData(prev =>
            prev.map(row => (row as Record<string, unknown>).id === (payload.new as Record<string, unknown>).id ? { ...row, ...payload.new as T } : row)
          )
        } else if (payload.eventType === 'DELETE') {
          setData(prev =>
            prev.filter(row => (row as Record<string, unknown>).id !== (payload.old as Record<string, unknown>).id)
          )
        }
      })
      .subscribe()

    channelRef.current = channel

    return () => {
      supabase.removeChannel(channel)
    }
  }, [enabled, fetchData, onInsert, table, filter?.column, filter?.operator, filter?.value, limit])

  return { data, loading, refetch: fetchData }
}
