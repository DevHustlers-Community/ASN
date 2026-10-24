import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './index.html',
    './src/**/*.{js,ts,jsx,tsx}',
  ],
  darkMode: ['class'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['"IBM Plex Sans Arabic"', '"IBM Plex Sans"', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
      },
      colors: {
        base: 'var(--bg-base)',
        surface: 'var(--bg-surface)',
        card: {
          DEFAULT: 'var(--bg-card)',
          foreground: 'var(--text-main)',
        },
        elevated: 'var(--bg-elevated)',
        overlay: 'var(--bg-overlay)',
        border: 'var(--border)',
        'border-subtle': 'var(--border-subtle)',
        primary: {
          DEFAULT: 'var(--primary)',
          hover: 'var(--primary-hover)',
          surface: 'var(--primary-surface)',
          foreground: '#ffffff',
        },
        status: {
          success: 'var(--status-success)',
          destructive: 'var(--status-destructive)',
          warning: 'var(--status-warning)',
          info: 'var(--status-info)',
        },
        text: {
          main: 'var(--text-main)',
          muted: 'var(--text-muted)',
          dim: 'var(--text-dim)',
        },
      },
      borderRadius: {
        card: 'var(--radius-card)',
        btn: 'var(--radius-btn)',
        pill: 'var(--radius-pill)',
      },
      lineHeight: {
        body: 'var(--leading-body)',
      },
    },
  },
  plugins: [],
};

export default config;
