"use client";

import { useState, useRef, useEffect } from "react";

interface Message {
  id: string;
  role: "user" | "coach";
  content: string;
  timestamp: Date;
  model?: string;
  processingTime?: number;
}

export default function CoachPage() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [messages]);

  useEffect(() => {
    if (inputRef.current) {
      inputRef.current.style.height = "auto";
      inputRef.current.style.height = Math.min(inputRef.current.scrollHeight, 120) + "px";
    }
  }, [input]);

  async function send() {
    const text = input.trim();
    if (!text || loading) return;

    const userMsg: Message = {
      id: crypto.randomUUID(),
      role: "user",
      content: text,
      timestamp: new Date(),
    };

    setMessages((prev) => [...prev, userMsg]);
    setInput("");
    setLoading(true);

    try {
      const res = await fetch("/api/coach", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text, conversationId }),
      });

      const data = await res.json();

      if (data.conversationId && !conversationId) {
        setConversationId(data.conversationId);
      }

      const coachMsg: Message = {
        id: crypto.randomUUID(),
        role: "coach",
        content: data.response || data.error || "No response",
        timestamp: new Date(),
        model: data.model,
        processingTime: data.processingTime,
      };

      setMessages((prev) => [...prev, coachMsg]);
    } catch {
      setMessages((prev) => [
        ...prev,
        {
          id: crypto.randomUUID(),
          role: "coach",
          content: "Failed to reach the coaching agent. Try again.",
          timestamp: new Date(),
        },
      ]);
    } finally {
      setLoading(false);
      inputRef.current?.focus();
    }
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  }

  return (
    <div className="mx-auto max-w-2xl flex flex-col h-[calc(100vh-80px)]">
      {/* Header */}
      <header className="px-4 py-6 text-center shrink-0">
        <h1 className="font-display text-3xl text-text-primary">Coach</h1>
        <p className="mt-1 text-sm text-text-tertiary">
          Same AI that powers the app — your training data, pace zones, and history are all here.
        </p>
      </header>

      {/* Messages */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto px-4 space-y-4">
        {messages.length === 0 && (
          <div className="py-16 text-center space-y-6">
            <div className="font-display text-4xl text-text-tertiary">AI</div>
            <p className="text-sm text-text-secondary max-w-sm mx-auto">
              Ask about your training, pacing, race prep, recovery — anything. The coach knows your workout history, pace segments, and fitness trajectory.
            </p>
            <div className="flex flex-wrap justify-center gap-2">
              {[
                "How did my week go?",
                "Am I ready for a half marathon?",
                "What should I do tomorrow?",
                "Are my easy runs too fast?",
                "Break down my last long run",
              ].map((prompt) => (
                <button
                  key={prompt}
                  onClick={() => { setInput(prompt); inputRef.current?.focus(); }}
                  className="rounded-lg border border-divider bg-bg-card px-3 py-1.5 font-mono text-[11px] text-text-secondary hover:border-coral/40 hover:text-coral transition-colors"
                >
                  {prompt}
                </button>
              ))}
            </div>
          </div>
        )}

        {messages.map((msg) => (
          <div key={msg.id} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
            <div
              className={`max-w-[85%] rounded-2xl px-4 py-3 ${
                msg.role === "user"
                  ? "bg-coral text-white rounded-br-sm"
                  : "bg-bg-card border border-divider rounded-bl-sm"
              }`}
            >
              <p className={`text-sm leading-relaxed whitespace-pre-wrap ${
                msg.role === "user" ? "text-white" : "text-text-primary"
              }`}>
                {msg.content}
              </p>

              {msg.role === "coach" && (msg.model || msg.processingTime) && (
                <div className="mt-2 flex items-center gap-2 font-mono text-[9px] text-text-tertiary">
                  {msg.model && <span>{msg.model}</span>}
                  {msg.processingTime && <span>{(msg.processingTime / 1000).toFixed(1)}s</span>}
                </div>
              )}
            </div>
          </div>
        ))}

        {loading && (
          <div className="flex justify-start">
            <div className="bg-bg-card border border-divider rounded-2xl rounded-bl-sm px-4 py-3">
              <div className="flex gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-text-tertiary animate-bounce" style={{ animationDelay: "0ms" }} />
                <span className="w-1.5 h-1.5 rounded-full bg-text-tertiary animate-bounce" style={{ animationDelay: "150ms" }} />
                <span className="w-1.5 h-1.5 rounded-full bg-text-tertiary animate-bounce" style={{ animationDelay: "300ms" }} />
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Input */}
      <div className="shrink-0 border-t border-divider bg-bg-base px-4 py-3">
        <div className="flex items-end gap-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask your coach..."
            rows={1}
            className="flex-1 resize-none rounded-xl border border-divider bg-bg-card px-4 py-3 text-sm text-text-primary placeholder-text-tertiary outline-none focus:border-coral/50 transition-colors leading-relaxed"
          />
          <button
            onClick={send}
            disabled={!input.trim() || loading}
            className="rounded-xl bg-coral px-4 py-3 text-white transition-colors hover:bg-coral-light disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <line x1="22" y1="2" x2="11" y2="13" />
              <polygon points="22 2 15 22 11 13 2 9 22 2" />
            </svg>
          </button>
        </div>

        {messages.length > 0 && (
          <div className="mt-2 text-center">
            <button
              onClick={() => { setMessages([]); setConversationId(null); }}
              className="font-mono text-[10px] text-text-tertiary hover:text-coral transition-colors"
            >
              new conversation
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
