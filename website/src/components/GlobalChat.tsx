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

export function GlobalChat({ userId, displayName, regimentTag, regimentId, isBanned }: GlobalChatProps) {
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

  // Fetch channels on mount
  useEffect(() => {
    async function loadChannels() {
      const { data } = await supabase
        .from('chat_channels')
        .select('id,name,type')
        .order('type')
        .order('name')

      if (data && data.length > 0) {
        setChannels(data as ChatChannel[])
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
        for (const msg of reversed) {
          const msgId = String(msg.id)
          if (!seenIds.current.has(msgId)) {
            seenIds.current.add(msgId)
            newMsgs.push(msg as ChatMessage)
          }
        }
        if (newMsgs.length > 0) {
          setWhisperMessages(prev => [...prev, ...newMsgs].slice(-MAX_MESSAGES))
        }
      }
    }
    loadWhispers()
  }, [])

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

  const sendMessage = useCallback(async (e: React.FormEvent) => {
    e.preventDefault()
    const text = input.trim()
    if (!text || cooldown || isBanned || !activeChannelId) return

    const chatName = regimentTag ? `${regimentTag} ${displayName}` : displayName
    setInput('')
    setCooldown(true)
    setTimeout(() => setCooldown(false), SEND_COOLDOWN_MS)

    const activeType = channels.find(c => c.id === activeChannelId)?.type || 'global'
    await supabase.from('chat_messages').insert({
      user_id: userId,
      display_name: chatName,
      message: text,
      channel: activeType,
      channel_id: activeChannelId,
    })
  }, [input, cooldown, isBanned, regimentTag, displayName, userId, activeChannelId, channels])

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
        <div className="w-96 h-[28rem] bg-slate-900 border border-slate-700 rounded-lg shadow-2xl flex flex-col">
          <div className="flex items-center justify-between px-4 py-2 border-b border-slate-700">
            <span className="text-sm font-semibold text-white">Chat</span>
            <button onClick={() => setOpen(false)} className="text-slate-400 hover:text-white text-lg">&times;</button>
          </div>

          {/* Channel tabs */}
          {channels.length > 1 && (
            <div className="flex gap-1 px-2 py-1 border-b border-slate-700 overflow-x-auto">
              {channels.map(ch => {
                const isActive = ch.id === activeChannelId
                const chUnread = channelUnread[ch.id] || 0
                const label = ch.type === 'regiment' ? `[${ch.name}]` : ch.name
                return (
                  <button
                    key={ch.id}
                    onClick={() => switchChannel(ch.id)}
                    className={`text-xs px-2 py-1 rounded whitespace-nowrap transition-colors ${
                      isActive
                        ? 'bg-sky-600 text-white'
                        : 'bg-slate-800 text-slate-400 hover:text-white hover:bg-slate-700'
                    }`}
                  >
                    {label}{chUnread > 0 && !isActive ? ` (${chUnread})` : ''}
                  </button>
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
                      [whisper {msg.user_id === userId ? 'to' : 'from'} {msg.display_name}]
                    </span>
                    <span className="text-slate-300">{msg.message}</span>
                  </>
                ) : (
                  <>
                    <a
                      href={`/player/${msg.user_id}`}
                      className={`hover:underline ${msg.user_id === userId ? 'text-cyan-400' : 'text-amber-400'}`}
                    >
                      {msg.display_name}
                    </a>
                    <span className="text-slate-300 ml-1">{msg.message}</span>
                  </>
                )}
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>

          <form onSubmit={sendMessage} className="p-2 border-t border-slate-700 flex gap-1">
            <input
              type="text"
              value={input}
              onChange={e => setInput(e.target.value)}
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
