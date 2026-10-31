import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'

interface SiteSettings {
  chat_enabled: boolean
  regiments_enabled: boolean
  download_enabled: boolean
  leaderboard_enabled: boolean
  registration_enabled: boolean
  appeal_enabled: boolean
  bugreports_enabled: boolean
  feedback_enabled: boolean
  game_version: string
  download_url: string
}

const DEFAULTS: SiteSettings = {
  chat_enabled: true,
  regiments_enabled: true,
  download_enabled: true,
  leaderboard_enabled: true,
  registration_enabled: true,
  appeal_enabled: true,
  bugreports_enabled: true,
  feedback_enabled: true,
  game_version: '',
  download_url: '',
}

export function useSiteSettings() {
  const [settings, setSettings] = useState<SiteSettings>(DEFAULTS)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function load() {
      const { data } = await supabase
        .from('site_settings')
        .select('key,value')

      if (data) {
        const merged = { ...DEFAULTS }
        for (const row of data) {
          if (row.key in merged) {
            (merged as Record<string, unknown>)[row.key] = row.value
          }
        }
        setSettings(merged)
      }
      setLoading(false)
    }

    load()

    const channel = supabase
      .channel(`site-settings-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'site_settings',
      } as never, (payload) => {
        const { key, value } = payload.new as { key: string; value: boolean | string }
        setSettings(prev => {
          if (key in prev) {
            return { ...prev, [key]: value }
          }
          return prev
        })
      })
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [])

  async function updateSetting(key: keyof SiteSettings, value: boolean | string) {
    setSettings(prev => ({ ...prev, [key]: value }))
    await supabase
      .from('site_settings')
      .update({ value, updated_at: new Date().toISOString() })
      .eq('key', key)
  }

  return { settings, loading, updateSetting }
}
