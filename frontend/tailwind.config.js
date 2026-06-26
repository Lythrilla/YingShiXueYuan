/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        sans: [
          'Inter',
          '"PingFang SC"',
          '"Microsoft YaHei"',
          'system-ui',
          'sans-serif',
        ],
      },
      colors: {
        // Warm near-black neutral scale — the primary surface/ text language.
        ink: {
          50: '#f7f7f8',
          100: '#ececee',
          200: '#dcdce0',
          300: '#bcbcc3',
          400: '#92929b',
          500: '#71717a',
          600: '#52525b',
          700: '#3f3f46',
          800: '#27272a',
          900: '#18181b',
          950: '#101012',
        },
        // Restrained indigo accent, used sparingly for focus / active states.
        accent: {
          50: '#eef1ff',
          100: '#e0e5ff',
          200: '#c6cfff',
          300: '#a3b0fc',
          400: '#7d88f6',
          500: '#5b63ec',
          600: '#4944d6',
          700: '#3d36b4',
        },
      },
      boxShadow: {
        card: '0 1px 2px rgba(16, 16, 18, 0.04), 0 1px 3px rgba(16, 16, 18, 0.05)',
        soft: '0 18px 50px -28px rgba(16, 16, 18, 0.28)',
        pop: '0 24px 60px -20px rgba(16, 16, 18, 0.35)',
      },
      keyframes: {
        'fade-up': {
          '0%': { opacity: '0', transform: 'translateY(8px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        'fade-in': {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
      },
      animation: {
        'fade-up': 'fade-up 0.45s cubic-bezier(0.16, 1, 0.3, 1) both',
        'fade-in': 'fade-in 0.3s ease-out both',
      },
    },
  },
  plugins: [],
}
