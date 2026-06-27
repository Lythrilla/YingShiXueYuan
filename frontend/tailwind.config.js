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
        // Warm sand → espresso neutral scale: the primary surface / text language.
        ink: {
          50: '#faf7f3',
          100: '#f3ece4',
          200: '#e8ddd0',
          300: '#d6c4b1',
          400: '#b4a08a',
          500: '#8d7b67',
          600: '#6b5b4b',
          700: '#4f4338',
          800: '#382f28',
          900: '#29221d',
          950: '#1b1612',
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
        card: '0 1px 2px rgba(60, 42, 30, 0.04), 0 8px 20px -18px rgba(60, 42, 30, 0.18)',
        soft: '0 14px 34px -26px rgba(60, 42, 30, 0.24)',
        pop: '0 24px 56px -26px rgba(60, 42, 30, 0.30)',
        glow: '0 10px 24px -16px rgba(219, 98, 56, 0.42)',
      },
      backgroundImage: {
        'warm-hero':
          'radial-gradient(120% 120% at 100% 0%, #db6238 0%, #c44d28 28%, #7a3a26 60%, #2b1d16 100%)',
        'warm-page':
          'linear-gradient(180deg, #fdf6ee 0%, #faf7f3 40%, #faf7f3 100%)',
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
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-10px)' },
        },
      },
      animation: {
        'fade-up': 'fade-up 0.5s cubic-bezier(0.16, 1, 0.3, 1) both',
        'fade-in': 'fade-in 0.3s ease-out both',
        float: 'float 9s ease-in-out infinite',
      },
    },
  },
  plugins: [],
}
