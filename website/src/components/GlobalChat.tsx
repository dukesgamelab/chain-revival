import { useState, useEffect, useRef } from 'react'
import { supabase } from '../lib/supabase'

interface ChatMessage {
  id: number
  display_name: string
  message: string
  created_at: string
  user_id: string
}

interface GlobalChatProps {
  userId: string
  displayName: string
  regimentTag: string | null
}

export function GlobalChat({ userId, displayName, regimentTag }: GlobalChatProps) {
  const [open, setOpen] = useState(false)
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [unread, setUnread] = useState(0)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const openRef = useRef(open)
  openRef.current = open

  useEffect(() => {
    async function loadHistory() {
      const { data } = await supabase
        .from('chat_messages')
        .select('id,display_name,message,created_at,user_id')
        .eq('channel', 'global')
        .order('created_at', { ascending: false })
        .limit(50)

      if (data) setMessages(data.reverse())
    }

    loadHistory()

    const channel = supabase
      .channel(`global-chat-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'chat_messages',
        filter: 'channel=eq.global',
      } as never, (payload) => {
        const msg = payload.new as ChatMessage
        setMessages(prev => [...prev.slice(-99), msg])
        if (!openRef.current) {
          setUnread(prev => prev + 1)
        }
      })
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [])

  useEffect(() => {
    if (open) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
      setUnread(0)
    }
  }, [open, messages.length])

  async function sendMessage(e: React.FormEvent) {
    e.preventDefault()
    const text = input.trim()
    if (!text) return

    const chatName = regimentTag ? `${regimentTag} ${displayName}` : displayName
    setInput('')

    await supabase.from('chat_messages').insert({
      user_id: userId,
      display_name: chatName,
      message: text,
      channel: 'global',
    })
  }

  return (
    <div className="fixed bottom-4 right-4 z-40">
      {open ? (
        <div className="w-80 h-96 bg-slate-900 border border-slate-700 rounded-lg shadow-2xl flex flex-col">
          <div className="flex items-center justify-between px-4 py-2 border-b border-slate-700">
            <span className="text-sm font-semibold text-white">Global Chat</span>
            <button onClick={() => setOpen(false)} className="text-slate-400 hover:text-white text-lg">&times;</button>
          </div>

          <div className="flex-1 overflow-y-auto px-3 py-2 space-y-1 text-sm">
            {messages.map(msg => (
              <div key={msg.id}>
                <span className={msg.user_id === userId ? 'text-cyan-400' : 'text-amber-400'}>
                  {msg.display_name}
                </span>
                <span className="text-slate-300 ml-1">{msg.message}</span>
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>

          <form onSubmit={sendMessage} className="p-2 border-t border-slate-700">
            <input
              type="text"
              value={input}
              onChange={e => setInput(e.target.value)}
              placeholder="Type a message..."
              className="w-full bg-slate-800 text-white text-sm rounded px-3 py-2 outline-none focus:ring-1 focus:ring-sky-500 placeholder-slate-500"
              maxLength={200}
            />
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
