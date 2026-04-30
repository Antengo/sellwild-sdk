import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        sans: ['DM Sans', 'system-ui', 'sans-serif'],
      },
      colors: {
        sw: {
          'green-dark': '#1d2627',
          green: '#415048',
          'green-light': '#728c55',
          yellow: '#e0d37a',
          blue: '#13274c',
          'blue-light': '#718cbb',
        },
      },
    },
  },
  plugins: [],
};

export default config;
