import { useState, useEffect, useRef, useCallback } from 'react'
import { supabase } from '../lib/supabase'

interface ChatMessage {
  id: number
  display_name: string
  message: string
  created_at: string
  user_id: string
  channel_id: string
  is_whisper: boolean
  whisper_to: string | null
}

interface ChatChannel {
  id: string
  name: string
  type: 'global' | 'regiment' | 'custom'
}

interface GlobalChatProps {
  userId: string
  displayName: string
  regimentTag: string | null
  regimentId: string | null
  isBanned: boolean
  isAdmin: boolean
  isModerator: boolean
}

const SEND_COOLDOWN_MS = 2000
const MAX_MESSAGES = 100

function formatChatTime(iso: string): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d.getTime())) return ''
  let h = d.getHours()
  const m = d.getMinutes()
  const ampm = h >= 12 ? 'PM' : 'AM'
  h = h % 12 || 12
  return `${h}:${m.toString().padStart(2, '0')} ${ampm}`
}

const TYPE_ORDER: Record<string, number> = { global: 0, regiment: 1, custom: 2 }
function sortChannels(chs: ChatChannel[]): ChatChannel[] {
  return [...chs].sort((a, b) => {
    const ao = TYPE_ORDER[a.type] ?? 2
    const bo = TYPE_ORDER[b.type] ?? 2
    return ao !== bo ? ao - bo : a.name.localeCompare(b.name)
  })
}

export function GlobalChat({ userId, displayName, regimentTag, regimentId: _regimentId, isBanned, isAdmin, isModerator }: GlobalChatProps) {
  const [open, setOpen] = useState(false)
  const [input, setInput] = useState('')
  const [unread, setUnread] = useState(0)
  const [cooldown, setCooldown] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const openRef = useRef(open)
  openRef.current = open

  const [channels, setChannels] = useState<ChatChannel[]>([])
  const [activeChannelId, setActiveChannelId] = useState<string>('')
  const activeChannelIdRef = useRef(activeChannelId)
  activeChannelIdRef.current = activeChannelId

  // Per-channel message storage
  const [channelMessages, setChannelMessages] = useState<Record<string, ChatMessage[]>>({})
  const [whisperMessages, setWhisperMessages] = useState<ChatMessage[]>([])
  const [channelUnread, setChannelUnread] = useState<Record<string, number>>({})
  const seenIds = useRef(new Set<string>())
  const loadedChannels = useRef(new Set<string>())
  const allPlayers = useRef<Record<string, string>>({})
  const playersLoaded = useRef(false)
  const [suggestions, setSuggestions] = useState<string[]>([])
  const [channelDialogOpen, setChannelDialogOpen] = useState(false)
  const [joinableChannels, setJoinableChannels] = useState<{ id: string; name: string; created_by: string }[]>([])
  const [newChannelName, setNewChannelName] = useState('')

  // Fetch channels on mount
  useEffect(() => {
    async function loadChannels() {
      const { data } = await supabase
        .from('chat_channels')
        .select('id,name,type')
        .order('type')
        .order('name')

      if (data && data.length > 0) {
        setChannels(sortChannels(data as ChatChannel[]))
        const globalCh = data.find((c: ChatChannel) => c.type === 'global')
        if (globalCh) {
          setActiveChannelId(globalCh.id)
          activeChannelIdRef.current = globalCh.id
        } else {
          setActiveChannelId(data[0].id)
          activeChannelIdRef.current = data[0].id
        }
      }
    }
    loadChannels()
  }, [])

  // Fetch history for active channel
  useEffect(() => {
    if (!activeChannelId) return
    if (loadedChannels.current.has(activeChannelId)) return

    async function loadHistory() {
      const { data } = await supabase
        .from('chat_messages')
        .select('id,display_name,message,created_at,user_id,channel_id,is_whisper,whisper_to')
        .eq('channel_id', activeChannelId)
        .order('created_at', { ascending: false })
        .limit(50)

      if (data) {
        loadedChannels.current.add(activeChannelId)
        const reversed = data.reverse()
        const newMsgs: ChatMessage[] = []
        for (const msg of reversed) {
          const msgId = String(msg.id)
          if (!seenIds.current.has(msgId)) {
            seenIds.current.add(msgId)
            newMsgs.push(msg as ChatMessage)
          }
        }
        if (newMsgs.length > 0) {
          setChannelMessages(prev => ({
            ...prev,
            [activeChannelId]: [...(prev[activeChannelId] || []), ...newMsgs].slice(-MAX_MESSAGES),
          }))
        }
      }
    }
    loadHistory()
  }, [activeChannelId])

  // Fetch whisper history once
  useEffect(() => {
    async function loadWhispers() {
      const { data } = await supabase
        .from('chat_messages')
        .select('id,display_name,message,created_at,user_id,channel_id,is_whisper,whisper_to')
        .eq('is_whisper', true)
        .order('created_at', { ascending: false })
        .limit(50)

      if (data) {
        const reversed = data.reverse()
        const newMsgs: ChatMessage[] = []
        const lookupIds: string[] = []
        for (const msg of reversed) {
          const msgId = String(msg.id)
          if (!seenIds.current.has(msgId)) {
            seenIds.current.add(msgId)
            newMsgs.push(msg as ChatMessage)
          }
          if (msg.user_id === userId && msg.whisper_to && !whisperNameCache.current[msg.whisper_to]) {
            if (!lookupIds.includes(msg.whisper_to)) lookupIds.push(msg.whisper_to)
          }
        }
        if (newMsgs.length > 0) {
          setWhisperMessages(prev => [...prev, ...newMsgs].slice(-MAX_MESSAGES))
        }
        if (lookupIds.length > 0) {
          const { data: profiles } = await supabase
            .from('player_profiles')
            .select('id,display_name')
            .in('id', lookupIds)
          if (profiles) {
            for (const p of profiles) {
              whisperNameCache.current[p.id as string] = p.display_name as string
            }
          }
        }
      }
    }
    loadWhispers()
  }, [userId])

  // Realtime subscription - no filter, RLS handles visibility
  useEffect(() => {
    const channel = supabase
      .channel(`chat-all-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'chat_messages',
      } as never, (payload) => {
        const msg = payload.new as ChatMessage
        const msgId = String(msg.id)
        if (seenIds.current.has(msgId)) return
        seenIds.current.add(msgId)

        const isWhisper = msg.is_whisper
        const chId = msg.channel_id
        const isSelf = msg.user_id === userId

        if (isWhisper) {
          setWhisperMessages(prev => [...prev, msg].slice(-MAX_MESSAGES))
        } else {
          setChannelMessages(prev => ({
            ...prev,
            [chId]: [...(prev[chId] || []), msg].slice(-MAX_MESSAGES),
          }))
        }

        if (!isSelf) {
          if (chId !== activeChannelIdRef.current || !openRef.current) {
            setChannelUnread(prev => ({ ...prev, [chId]: (prev[chId] || 0) + 1 }))
          }
          if (!openRef.current) {
            setUnread(prev => prev + 1)
          }
        }
      })
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [userId])

  // Auto-scroll
  useEffect(() => {
    if (open) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
      setUnread(0)
    }
  }, [open, channelMessages, whisperMessages])

  const switchChannel = useCallback((chId: string) => {
    setActiveChannelId(chId)
    activeChannelIdRef.current = chId
    setChannelUnread(prev => ({ ...prev, [chId]: 0 }))
  }, [])

  const [systemMsg, setSystemMsg] = useState<string | null>(null)
  const whisperNameCache = useRef<Record<string, string>>({})

  const sendMessage = useCallback(async (e: React.FormEvent) => {
    e.preventDefault()
    const text = input.trim()
    if (!text || cooldown || isBanned || !activeChannelId) return

    const chatName = regimentTag ? `${regimentTag} ${displayName}` : displayName
    setInput('')
    setCooldown(true)
    setTimeout(() => setCooldown(false), SEND_COOLDOWN_MS)

    if (text.startsWith('/w ')) {
      const rest = text.slice(3).trim()
      const spaceIdx = rest.indexOf(' ')
      if (spaceIdx < 1) {
        setSystemMsg('Usage: /w PlayerName message')
        setTimeout(() => setSystemMsg(null), 4000)
        return
      }
      const targetName = rest.slice(0, spaceIdx).trim()
      const whisperText = rest.slice(spaceIdx + 1).trim()
      if (!whisperText) {
        setSystemMsg('Usage: /w PlayerName message')
        setTimeout(() => setSystemMsg(null), 4000)
        return
      }
      const { data: players } = await supabase
        .from('player_profiles')
        .select('id,display_name')
        .eq('display_name', targetName)
        .limit(1)
      if (!players || players.length === 0) {
        setSystemMsg(`Player '${targetName}' not found.`)
        setTimeout(() => setSystemMsg(null), 4000)
        return
      }
      const targetId = players[0].id as string
      whisperNameCache.current[targetId] = players[0].display_name as string
      if (targetId === userId) {
        setSystemMsg("You can't whisper to yourself.")
        setTimeout(() => setSystemMsg(null), 4000)
        return
      }
      await supabase.from('chat_messages').insert({
        user_id: userId,
        display_name: chatName,
        message: whisperText,
        channel: 'global',
        channel_id: activeChannelId,
        is_whisper: true,
        whisper_to: targetId,
      })
      return
    }

    const activeType = channels.find(c => c.id === activeChannelId)?.type || 'global'
    await supabase.from('chat_messages').insert({
      user_id: userId,
      display_name: chatName,
      message: text,
      channel: activeType,
      channel_id: activeChannelId,
    })
  }, [input, cooldown, isBanned, regimentTag, displayName, userId, activeChannelId, channels])

  const inputRef = useRef('')

  const updateSuggestions = useCallback(() => {
    const val = inputRef.current
    if (val.startsWith('/w ')) {
      const partial = val.slice(3).trim().toLowerCase()
      const matches = Object.values(allPlayers.current)
        .filter(name => !partial || name.toLowerCase().startsWith(partial))
        .slice(0, 8)
      setSuggestions(matches)
    } else {
      setSuggestions([])
    }
  }, [])

  const fetchAllPlayers = useCallback(async () => {
    if (playersLoaded.current) return
    const { data } = await supabase
      .from('player_profiles')
      .select('id,display_name')
      .neq('id', userId)
      .order('display_name')
    if (data) {
      playersLoaded.current = true
      for (const p of data) {
        allPlayers.current[p.id as string] = p.display_name as string
      }
      updateSuggestions()
    }
  }, [userId, updateSuggestions])

  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value
    setInput(val)
    inputRef.current = val
    if (val.startsWith('/w ')) {
      if (!playersLoaded.current) fetchAllPlayers()
    }
    updateSuggestions()
  }, [fetchAllPlayers, updateSuggestions])

  const stripTag = useCallback((name: string) => {
    const parts = name.split(' ')
    if (parts.length >= 2 && parts[0].length <= 5 && parts[0] === parts[0].toUpperCase()) {
      return parts.slice(1).join(' ')
    }
    return name
  }, [])

  const clickToWhisper = useCallback((name: string) => {
    const bare = stripTag(name)
    setInput(`/w ${bare} `)
    inputRef.current = `/w ${bare} `
    setSuggestions([])
  }, [stripTag])

  const pickSuggestion = useCallback((name: string) => {
    setInput(`/w ${name} `)
    setSuggestions([])
  }, [])

  const fetchJoinableChannels = useCallback(async () => {
    const { data } = await supabase.rpc('list_custom_channels')
    if (data) {
      setJoinableChannels(data as { id: string; name: string; created_by: string }[])
    }
  }, [])

  const openChannelDialog = useCallback(() => {
    setChannelDialogOpen(true)
    setNewChannelName('')
    fetchJoinableChannels()
  }, [fetchJoinableChannels])

  const createChannel = useCallback(async () => {
    const name = newChannelName.trim()
    if (!name) return
    const { error } = await supabase.rpc('create_custom_channel', { p_name: name })
    if (error) {
      setSystemMsg('Could not create channel.')
      setTimeout(() => setSystemMsg(null), 4000)
      return
    }
    setChannelDialogOpen(false)
    setNewChannelName('')
    const { data: refreshed } = await supabase
      .from('chat_channels')
      .select('id,name,type')
      .order('type')
      .order('name')
    if (refreshed) setChannels(sortChannels(refreshed as ChatChannel[]))
  }, [newChannelName])

  const joinChannel = useCallback(async (channelId: string) => {
    await supabase.from('chat_channel_members').insert({ channel_id: channelId, user_id: userId })
    setChannelDialogOpen(false)
    const { data: refreshed } = await supabase
      .from('chat_channels')
      .select('id,name,type')
      .order('type')
      .order('name')
    if (refreshed) setChannels(sortChannels(refreshed as ChatChannel[]))
  }, [userId])

  const leaveChannel = useCallback(async (channelId: string) => {
    await supabase
      .from('chat_channel_members')
      .delete()
      .eq('channel_id', channelId)
      .eq('user_id', userId)
    if (activeChannelId === channelId) {
      const globalCh = channels.find(c => c.type === 'global')
      if (globalCh) {
        setActiveChannelId(globalCh.id)
        activeChannelIdRef.current = globalCh.id
      }
    }
    const { data: refreshed } = await supabase
      .from('chat_channels')
      .select('id,name,type')
      .order('type')
      .order('name')
    if (refreshed) setChannels(sortChannels(refreshed as ChatChannel[]))
  }, [userId, activeChannelId, channels])

  const deleteChannel = useCallback(async (channelId: string) => {
    const { error } = await supabase.rpc('delete_custom_channel', { p_channel_id: channelId })
    if (error) {
      setSystemMsg('Could not delete channel.')
      setTimeout(() => setSystemMsg(null), 4000)
      return
    }
    if (activeChannelId === channelId) {
      const globalCh = channels.find(c => c.type === 'global')
      if (globalCh) {
        setActiveChannelId(globalCh.id)
        activeChannelIdRef.current = globalCh.id
      }
    }
    const { data: refreshed } = await supabase
      .from('chat_channels')
      .select('id,name,type')
      .order('type')
      .order('name')
    if (refreshed) setChannels(sortChannels(refreshed as ChatChannel[]))
    fetchJoinableChannels()
  }, [activeChannelId, channels, fetchJoinableChannels])

  // Build display messages: channel messages + whispers, sorted by time
  const displayMessages = (() => {
    const chMsgs = channelMessages[activeChannelId] || []
    const all = [...chMsgs, ...whisperMessages]
    all.sort((a, b) => a.created_at.localeCompare(b.created_at))
    return all
  })()

  return (
    <div className="fixed bottom-4 right-4 z-40">
      {open ? (
        <div className="w-96 h-[28rem] bg-slate-900 border border-slate-700 rounded-lg shadow-2xl flex flex-col relative">
          <div className="flex items-center justify-between px-4 py-2 border-b border-slate-700">
            <span className="text-sm font-semibold text-white">Chat</span>
            <div className="flex gap-1">
              <button onClick={openChannelDialog} className="text-slate-400 hover:text-white text-sm px-1" title="Create or join a channel">+</button>
              <button onClick={() => setOpen(false)} className="text-slate-400 hover:text-white text-lg">&times;</button>
            </div>
          </div>

          {/* Channel tabs */}
          {channels.length > 1 && (
            <div className="flex gap-1 px-2 py-1 border-b border-slate-700 overflow-x-auto">
              {channels.map(ch => {
                const isActive = ch.id === activeChannelId
                const chUnread = channelUnread[ch.id] || 0
                const label = ch.type === 'regiment' ? `[${ch.name}]` : ch.name
                return (
                  <div key={ch.id} className="flex items-center">
                    <button
                      onClick={() => switchChannel(ch.id)}
                      className={`text-xs px-2 py-1 rounded-l whitespace-nowrap transition-colors ${
                        isActive
                          ? 'bg-sky-600 text-white'
                          : 'bg-slate-800 text-slate-400 hover:text-white hover:bg-slate-700'
                      } ${ch.type !== 'custom' ? 'rounded-r' : ''}`}
                    >
                      {label}{chUnread > 0 && !isActive ? ` (${chUnread})` : ''}
                    </button>
                    {ch.type === 'custom' && (
                      <button
                        onClick={() => leaveChannel(ch.id)}
                        className="text-xs px-1 py-1 rounded-r bg-slate-800 text-slate-500 hover:text-red-400 hover:bg-slate-700 transition-colors"
                        title="Leave channel"
                      >
                        x
                      </button>
                    )}
                  </div>
                )
              })}
            </div>
          )}

          <div className="flex-1 overflow-y-auto px-3 py-2 space-y-1 text-sm">
            {displayMessages.map(msg => (
              <div key={msg.id}>
                <span className="text-slate-500 text-xs mr-1">{formatChatTime(msg.created_at)}</span>
                {msg.is_whisper ? (
                  <>
                    <span className="text-fuchsia-400 text-xs mr-1">
                      [whisper {msg.user_id === userId ? 'to ' : 'from '}
                      {msg.user_id === userId ? (
                        whisperNameCache.current[msg.whisper_to || ''] || msg.whisper_to
                      ) : (
                        <button
                          type="button"
                          onClick={() => clickToWhisper(msg.display_name)}
                          className="hover:underline text-fuchsia-400 cursor-pointer"
                        >
                          {msg.display_name}
                        </button>
                      )}]
                    </span>
                    <span className="text-slate-300">{msg.message}</span>
                  </>
                ) : (
                  <>
                    {msg.user_id === userId ? (
                      <span className="text-cyan-400">{msg.display_name}</span>
                    ) : (
                      <button
                        type="button"
                        onClick={() => clickToWhisper(msg.display_name)}
                        className={`hover:underline text-amber-400 cursor-pointer`}
                      >
                        {msg.display_name}
                      </button>
                    )}
                    <span className="text-slate-300 ml-1">{msg.message}</span>
                  </>
                )}
              </div>
            ))}
            {systemMsg && (
              <div className="text-red-400 text-xs">{systemMsg}</div>
            )}
            <div ref={messagesEndRef} />
          </div>

          {suggestions.length > 0 && (
            <div className="px-2 pb-1">
              <div className="bg-slate-800 border border-slate-600 rounded p-1 flex flex-wrap gap-1">
                {suggestions.map(name => (
                  <button
                    key={name}
                    type="button"
                    onClick={() => pickSuggestion(name)}
                    className="text-xs bg-slate-700 hover:bg-slate-600 text-slate-200 rounded px-2 py-1 transition-colors"
                  >
                    {name}
                  </button>
                ))}
              </div>
            </div>
          )}

          <form onSubmit={sendMessage} className="p-2 border-t border-slate-700 flex gap-1">
            <input
              type="text"
              value={input}
              onChange={handleInputChange}
              placeholder={isBanned ? 'You are banned from chat' : cooldown ? 'Wait...' : 'Type a message...'}
              disabled={cooldown || isBanned}
              className="flex-1 bg-slate-800 text-white text-sm rounded px-3 py-2 outline-none focus:ring-1 focus:ring-sky-500 placeholder-slate-500 disabled:opacity-50"
              maxLength={200}
            />
            <button
              type="submit"
              disabled={cooldown || isBanned || !input.trim()}
              className="bg-sky-600 hover:bg-sky-500 disabled:bg-slate-700 disabled:text-slate-500 text-white text-sm rounded px-3 py-2 transition-colors"
            >
              Send
            </button>
          </form>

          {channelDialogOpen && (
            <div className="absolute inset-0 bg-slate-900 rounded-lg flex flex-col z-10">
              <div className="flex items-center justify-between px-4 py-2 border-b border-slate-700">
                <span className="text-sm font-semibold text-white">Channels</span>
                <button onClick={() => setChannelDialogOpen(false)} className="text-slate-400 hover:text-white text-lg">&times;</button>
              </div>
              <div className="flex-1 overflow-y-auto px-4 py-3 space-y-4">
                <div>
                  <p className="text-xs text-slate-400 mb-1">Create channel</p>
                  <div className="flex gap-1">
                    <input
                      type="text"
                      value={newChannelName}
                      onChange={e => setNewChannelName(e.target.value)}
                      placeholder="Channel name"
                      maxLength={20}
                      className="flex-1 bg-slate-800 text-white text-sm rounded px-2 py-1 outline-none focus:ring-1 focus:ring-sky-500 placeholder-slate-500"
                    />
                    <button
                      onClick={createChannel}
                      disabled={!newChannelName.trim()}
                      className="bg-sky-600 hover:bg-sky-500 disabled:bg-slate-700 disabled:text-slate-500 text-white text-xs rounded px-3 py-1 transition-colors"
                    >
                      Create
                    </button>
                  </div>
                </div>
                <hr className="border-slate-700" />
                <div>
                  <p className="text-xs text-slate-400 mb-1">Custom channels</p>
                  {joinableChannels.length === 0 ? (
                    <p className="text-xs text-slate-500">No custom channels yet.</p>
                  ) : (
                    <div className="space-y-1">
                      {joinableChannels.map(ch => {
                        const joined = channels.some(c => c.id === ch.id)
                        const canDelete = ch.created_by === userId || isAdmin || isModerator
                        return (
                          <div key={ch.id} className="flex items-center justify-between">
                            <span className={`text-sm ${joined ? 'text-slate-500' : 'text-slate-300'}`}>
                              {ch.name}{joined ? ' (joined)' : ''}
                            </span>
                            <div className="flex gap-1">
                              {!joined && (
                                <button
                                  onClick={() => joinChannel(ch.id)}
                                  className="text-xs bg-sky-600 hover:bg-sky-500 text-white rounded px-2 py-1 transition-colors"
                                >
                                  Join
                                </button>
                              )}
                              {canDelete && (
                                <button
                                  onClick={() => deleteChannel(ch.id)}
                                  className="text-xs bg-red-700 hover:bg-red-600 text-white rounded px-2 py-1 transition-colors"
                                >
                                  Delete
                                </button>
                              )}
                            </div>
                          </div>
                        )
                      })}
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}
        </div>
      ) : (
        <button
          onClick={() => setOpen(true)}
          className="bg-sky-600 hover:bg-sky-500 text-white rounded-full w-12 h-12 flex items-center justify-center shadow-lg transition-colors relative"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
          </svg>
          {unread > 0 && (
            <span className="absolute -top-1 -right-1 bg-red-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center font-bold">
              {unread > 9 ? '9+' : unread}
            </span>
          )}
        </button>
      )}
    </div>
  )
}
