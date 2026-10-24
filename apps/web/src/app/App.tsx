import React, { useState, useId } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Input } from '@/components/ui/input';

export function App() {
  const [theme, setTheme] = useState<'oled' | 'dim' | 'light'>('oled');
  const [accent, setAccent] = useState<'emerald' | 'indigo' | 'amber' | 'crimson' | 'cyan'>('emerald');
  const inputId = useId();

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
          <img
            src="/logo.svg"
            alt="شعار ASN"
            className="h-10 w-10 rounded-btn object-contain shadow-sm"
          />
          <div>
            <div className="text-base font-bold flex items-center gap-2">
              <span>شبكة ASN (Arabian Social Network)</span>
              <Badge variant="default">v0.1.0 Scaffolding</Badge>
            </div>
            <p className="text-xs text-text-muted">بيئة التشغيل المحلية والخطوط مثبتة بدون أي CDN خارجي 🚀</p>
          </div>
        </div>

        {/* Quick Theme Switchers */}
        <div className="flex items-center gap-2 text-xs">
          <div className="flex bg-surface border border-border p-1 rounded-btn" role="group" aria-label="تبديل النمط">
            <button
              type="button"
              onClick={() => handleThemeChange('oled')}
              aria-pressed={theme === 'oled'}
              aria-label="نمط OLED الأسود"
              className={`px-3 py-1 rounded text-xs transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-text ${
                theme === 'oled' ? 'bg-primary text-primary-foreground font-bold' : 'text-text-muted hover:text-text-main'
              }`}
            >
              OLED
            </button>
            <button
              type="button"
              onClick={() => handleThemeChange('dim')}
              aria-pressed={theme === 'dim'}
              aria-label="نمط Dim الداكن"
              className={`px-3 py-1 rounded text-xs transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-text ${
                theme === 'dim' ? 'bg-primary text-primary-foreground font-bold' : 'text-text-muted hover:text-text-main'
              }`}
            >
              Dim
            </button>
            <button
              type="button"
              onClick={() => handleThemeChange('light')}
              aria-pressed={theme === 'light'}
              aria-label="نمط Light الفاتح"
              className={`px-3 py-1 rounded text-xs transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-text ${
                theme === 'light' ? 'bg-primary text-primary-foreground font-bold' : 'text-text-muted hover:text-text-main'
              }`}
            >
              Light
            </button>
          </div>

          <div className="flex gap-1" role="group" aria-label="اختيار اللون البارز">
            {(['emerald', 'indigo', 'amber', 'crimson', 'cyan'] as const).map((acc) => (
              <button
                key={acc}
                type="button"
                onClick={() => handleAccentChange(acc)}
                aria-pressed={accent === acc}
                aria-label={`لون اللكنة ${acc}`}
                className={`w-6 h-6 rounded-full border-2 transition flex items-center justify-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-text ${
                  accent === acc ? 'scale-110 border-white ring-2 ring-primary/40' : 'border-transparent opacity-70 hover:opacity-100'
                }`}
                style={{
                  backgroundColor:
                    acc === 'emerald' ? '#10b981' : acc === 'indigo' ? '#4f46e5' : acc === 'amber' ? '#f59e0b' : acc === 'crimson' ? '#e11d48' : '#06b6d4',
                }}
              >
                {accent === acc && (
                  <span
                    className={`text-[10px] font-bold leading-none ${
                      acc === 'indigo' || acc === 'crimson' ? 'text-white' : 'text-black'
                    }`}
                  >
                    ✓
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>
      </header>

      {/* Main Content Area */}
      <main className="max-w-2xl mx-auto space-y-6">
        {/* Verification Success Box */}
        <div className="p-4 rounded-card border border-status-success/30 bg-status-success/10 text-xs text-status-success-foreground flex items-center justify-between">
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
                <div className="text-xs text-text-muted flex items-center gap-1.5">
                  <span>مهندس نظم موزعة</span>
                  <span>·</span>
                  <span className="inline-flex items-center gap-1 text-status-success-foreground font-medium">
                    <span className="inline-block w-1.5 h-1.5 rounded-full bg-status-success" />
                    <span>متصل</span>
                  </span>
                  <span>·</span>
                  <span>منذ قليل</span>
                </div>
              </div>
            </div>
            <Badge variant="info">dev-opaque-v1</Badge>
          </div>

          <p className="text-sm text-text-main leading-relaxed">
            تم بنجاح تأسيس مشروع الـ Frontend بنظام Monorepo مع دعم كامل للـ RTL والخط العربي الشاشي المريح بدون الحاجة لأي اتصال خارجي. الخطوط تعمل محلياً 100%!
          </p>

          <div className="flex items-center justify-between pt-2 border-t border-border text-xs text-text-muted">
            <div className="flex items-center gap-4">
              <Button variant="ghost" size="sm" className="gap-1 hover:text-status-destructive-foreground">
                <span>♡</span> <span className="font-mono">42</span>
              </Button>
              <Button variant="ghost" size="sm" className="gap-1 hover:text-primary-text">
                <span>💬</span> <span className="font-mono">18</span>
              </Button>
              <Button variant="ghost" size="sm" className="gap-1 hover:text-status-info-foreground">
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
          <label htmlFor={inputId} className="text-xs font-semibold text-text-muted block">
            حقل كتابة تجريبي مع دعم الـ RTL والأيقونة:
          </label>
          <Input id={inputId} placeholder="اكتب رسالة أو تعليقاً هنا..." startIcon={<span>✍️</span>} />
        </div>
      </main>
    </div>
  );
}
