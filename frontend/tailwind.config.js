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
        // Neutral gray scale: the primary surface / text language.
        ink: {
          50: '#fafafa',
          100: '#f4f4f5',
          200: '#e4e4e7',
          300: '#d4d4d8',
          400: '#a1a1aa',
          500: '#71717a',
          600: '#52525b',
          700: '#3f3f46',
          800: '#27272a',
          900: '#18181b',
          950: '#09090b',
        },
        // Warm terracotta / clay accent — inviting, used for primary actions & highlights.
        accent: {
          50: '#fdf4ef',
          100: '#fbe6da',
          200: '#f6cbb4',
          300: '#efa784',
          400: '#e6815a',
          500: '#db6238',
          600: '#c44d28',
          700: '#a33d22',
        },
        // Soft golden secondary, for subtle warm highlights.
        gold: {
          50: '#fdf8ee',
          100: '#f9edcf',
          200: '#f1d99c',
          300: '#e8c069',
          400: '#dfa63f',
        },
      },
      boxShadow: {
        card: '0 1px 2px rgba(60, 42, 30, 0.04), 0 10px 26px -22px rgba(60, 42, 30, 0.24)',
        soft: '0 18px 48px -26px rgba(60, 42, 30, 0.26)',
        pop: '0 30px 70px -28px rgba(60, 42, 30, 0.34)',
        glow: '0 18px 42px -22px rgba(219, 98, 56, 0.55)',
        glass: '0 18px 52px -34px rgba(74, 45, 28, 0.42), inset 0 1px 0 rgba(255, 255, 255, 0.72)',
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
        'fade-up': 'fade-up 0.4s cubic-bezier(0.16, 1, 0.3, 1) both',
        'fade-in': 'fade-in 0.25s ease-out both',
      },
    },
  },
  plugins: [],
}
