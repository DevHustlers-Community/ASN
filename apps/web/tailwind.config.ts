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
          DEFAULT: 'rgb(var(--primary-rgb) / <alpha-value>)',
          hover: 'var(--primary-hover)',
          foreground: 'var(--primary-foreground)',
          text: 'var(--primary-text)',
        },
        status: {
          success: {
            DEFAULT: 'rgb(var(--status-success-rgb) / <alpha-value>)',
            foreground: 'var(--status-success-foreground)',
          },
          destructive: {
            DEFAULT: 'rgb(var(--status-destructive-rgb) / <alpha-value>)',
            foreground: 'var(--status-destructive-foreground)',
          },
          warning: {
            DEFAULT: 'rgb(var(--status-warning-rgb) / <alpha-value>)',
            foreground: 'var(--status-warning-foreground)',
          },
          info: {
            DEFAULT: 'rgb(var(--status-info-rgb) / <alpha-value>)',
            foreground: 'var(--status-info-foreground)',
          },
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
