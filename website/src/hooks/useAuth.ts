import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { User, Session } from '@supabase/supabase-js'

interface Profile {
  prestige_points: number
  rank: number
  regiment_id: string | null
  regiment_tag: string | null
  is_admin: boolean
  is_moderator: boolean
  is_banned: boolean
  ban_reason: string | null
  display_name: string
}

interface AuthState {
  user: User | null
  session: Session | null
  profile: Profile | null
  loading: boolean
  signIn: (email: string, password: string) => Promise<{ error: string | null }>
  signUp: (email: string, password: string, displayName: string) => Promise<{ error: string | null }>
  signOut: () => Promise<void>
}

export function useAuth(): AuthState {
  const [user, setUser] = useState<User | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)

  async function fetchProfile(userId: string) {
    const { data } = await supabase
      .from('player_profiles')
      .select('display_name,prestige_points,rank,regiment_id,is_admin,is_moderator,is_banned,ban_reason,regiments(tag)')
      .eq('id', userId)
      .single()

    if (data) {
      const regArr = data.regiments as unknown as { tag: string }[] | null
      const regiment = regArr?.[0] ?? null
      setProfile({
        display_name: data.display_name,
        prestige_points: data.prestige_points,
        rank: data.rank,
        regiment_id: data.regiment_id,
        regiment_tag: regiment?.tag ?? null,
        is_admin: data.is_admin,
        is_moderator: data.is_moderator,
        is_banned: data.is_banned,
        ban_reason: data.ban_reason,
      })
    }
  }

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session: s } }) => {
      setSession(s)
      setUser(s?.user ?? null)
      if (s?.user) fetchProfile(s.user.id)
      setLoading(false)
    })

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, s) => {
      setSession(s)
      setUser(s?.user ?? null)
      if (s?.user) {
        fetchProfile(s.user.id)
      } else {
        setProfile(null)
      }
    })

    return () => subscription.unsubscribe()
  }, [])

  async function signIn(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error: error?.message ?? null }
  }

  async function signUp(email: string, password: string, displayName: string) {
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { display_name: displayName } },
    })
    return { error: error?.message ?? null }
  }

  async function signOut() {
    await supabase.auth.signOut()
    setProfile(null)
  }

  return { user, session, profile, loading, signIn, signUp, signOut }
}
