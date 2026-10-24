import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Input } from '@/components/ui/input';

export function App() {
  const [theme, setTheme] = useState<'oled' | 'dim' | 'light'>('oled');
  const [accent, setAccent] = useState<'emerald' | 'indigo' | 'amber' | 'crimson' | 'cyan'>('emerald');

  const handleThemeChange = (newTheme: 'oled' | 'dim' | 'light') => {
    setTheme(newTheme);
    document.documentElement.setAttribute('data-theme', newTheme);
  };

  const handleAccentChange = (newAccent: 'emerald' | 'indigo' | 'amber' | 'crimson' | 'cyan') => {
    setAccent(newAccent);
    document.documentElement.setAttribute('data-accent', newAccent);
  };

  return (
    <div className="min-h-screen bg-base text-text-main p-4 md:p-8">
      {/* Top Navbar */}
      <header className="max-w-5xl mx-auto mb-8 border-b border-border pb-4 flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <img src="/logo.png" alt="شعار تواصل ASN" className="h-10 w-auto rounded-btn object-contain shadow-sm bg-white/90 p-1" />
          <div>
            <div className="text-base font-bold flex items-center gap-2">
              <span>شبكة تواصل (ASN)</span>
              <Badge variant="default">v0.1.0 Scaffolding</Badge>
            </div>
            <p className="text-xs text-text-muted">بيئة التشغيل المحلية والخطوط مثبتة بدون أي CDN خارجي 🚀</p>
          </div>
        </div>

        {/* Quick Theme Switchers */}
        <div className="flex items-center gap-2 text-xs">
          <div className="flex bg-surface border border-border p-1 rounded-btn">
            <button
              onClick={() => handleThemeChange('oled')}
              className={`px-2.5 py-1 rounded text-xs transition ${theme === 'oled' ? 'bg-primary text-white font-bold' : 'text-text-muted hover:text-text-main'}`}
            >
              OLED
            </button>
            <button
              onClick={() => handleThemeChange('dim')}
              className={`px-2.5 py-1 rounded text-xs transition ${theme === 'dim' ? 'bg-primary text-white font-bold' : 'text-text-muted hover:text-text-main'}`}
            >
              Dim
            </button>
            <button
              onClick={() => handleThemeChange('light')}
              className={`px-2.5 py-1 rounded text-xs transition ${theme === 'light' ? 'bg-primary text-white font-bold' : 'text-text-muted hover:text-text-main'}`}
            >
              Light
            </button>
          </div>

          <div className="flex gap-1">
            {(['emerald', 'indigo', 'amber', 'crimson', 'cyan'] as const).map((acc) => (
              <button
                key={acc}
                onClick={() => handleAccentChange(acc)}
                className={`w-6 h-6 rounded-full border-2 transition ${accent === acc ? 'scale-110 border-white' : 'border-transparent opacity-70 hover:opacity-100'}`}
                style={{
                  backgroundColor:
                    acc === 'emerald' ? '#10b981' : acc === 'indigo' ? '#6366f1' : acc === 'amber' ? '#f59e0b' : acc === 'crimson' ? '#f43f5e' : '#06b6d4',
                }}
                title={acc}
              />
            ))}
          </div>
        </div>
      </header>

      {/* Main Content Area */}
      <main className="max-w-2xl mx-auto space-y-6">
        {/* Verification Success Box */}
        <div className="p-4 rounded-card border border-status-success/30 bg-status-success/10 text-xs text-emerald-300 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span>🛡️</span>
            <span>تم تهيئة هيكلية المشروع والخطوط المحلية (IBM Plex Sans Arabic + JetBrains Mono) بنجاح تام!</span>
          </div>
          <Badge variant="success">Local Fonts Active</Badge>
        </div>

        {/* Post Card Preview */}
        <article className="p-5 rounded-card border border-border bg-card shadow-sm space-y-4">
          <div className="flex items-start justify-between">
            <div className="flex items-center gap-3">
              <Avatar presence="online">
                <AvatarFallback>ع</AvatarFallback>
              </Avatar>
              <div>
                <div className="flex items-center gap-2">
                  <span className="font-bold text-sm text-text-main">علي القحطاني</span>
                  <span className="text-xs text-text-dim font-mono">@ali_dev</span>
                </div>
                <div className="text-xs text-text-muted">مهندس نظم موزعة · منذ قليل</div>
              </div>
            </div>
            <Badge variant="info">dev-opaque-v1</Badge>
          </div>

          <p className="text-sm text-text-main leading-relaxed">
            تم بنجاح تأسيس مشروع الـ Frontend بنظام Monorepo مع دعم كامل للـ RTL والخط العربي الشاشي المريح بدون الحاجة لأي اتصال خارجي. الخطوط تعمل محلياً 100%!
          </p>

          <div className="flex items-center justify-between pt-2 border-t border-border text-xs text-text-muted">
            <div className="flex items-center gap-4">
              <Button variant="ghost" size="sm" className="gap-1.5 hover:text-rose-400">
                <span>♡</span> <span className="font-mono">42</span>
              </Button>
              <Button variant="ghost" size="sm" className="gap-1.5 hover:text-primary">
                <span>💬</span> <span className="font-mono">18</span>
              </Button>
              <Button variant="ghost" size="sm" className="gap-1.5 hover:text-sky-400">
                <span>🔁</span> <span className="font-mono">9</span>
              </Button>
            </div>
            <Button variant="secondary" size="sm">
              متابعة الحساب
            </Button>
          </div>
        </article>

        {/* Input demo */}
        <div className="p-4 rounded-card border border-border bg-surface space-y-3">
          <label className="text-xs font-semibold text-text-muted block">حقل كتابة تجريبي مع دعم الـ RTL والأيقونة:</label>
          <Input placeholder="اكتب رسالة أو تعليقاً هنا..." startIcon={<span>✍️</span>} />
        </div>
      </main>
    </div>
  );
}
