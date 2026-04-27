module.exports = {
  content: [
    './node_modules/@relume_io/relume-ui/dist/**/*.{js,ts,jsx,tsx}',
    './*.{js,ts,jsx,tsx}',
    './src/**/*.{js,ts,jsx,tsx}',
    './home/**/*.{js,ts,jsx,tsx}',
    './download/**/*.{js,ts,jsx,tsx}',
    './pricing/**/*.{js,ts,jsx,tsx}',
    './legal/**/*.{js,ts,jsx,tsx}',
  ],
  presets: [require('@relume_io/relume-tailwind')],
  theme: {
    extend: {
      fontFamily: {
        sans: [
          'Geist',
          'Geist Variable',
          '-apple-system',
          'BlinkMacSystemFont',
          'Segoe UI',
          'system-ui',
          'sans-serif',
        ],
      },
      colors: {
        background: {
          DEFAULT: '#FCFCFC',
          primary: '#FCFCFC',
          secondary: '#F6F6F7',
          tertiary: '#737378',
          alternative: '#161618',
        },
        border: {
          DEFAULT: '#EBEBED',
          primary: '#EBEBED',
          secondary: '#A1A1A6',
          tertiary: '#222224',
          alternative: '#FFFFFF',
        },
        text: {
          DEFAULT: '#161618',
          primary: '#161618',
          secondary: '#A1A1A6',
          alternative: '#FFFFFF',
        },
        link: {
          DEFAULT: '#161618',
          primary: '#161618',
          secondary: '#737378',
          alternative: '#FFFFFF',
        },
        brand: {
          black: '#161618',
          white: '#FCFCFC',
          blue: '#437DFB',
          'sky-blue': '#0066FF',
        },
        neutral: {
          DEFAULT: '#737378',
          black: '#161618',
          white: '#FCFCFC',
          lightest: '#F6F6F7',
          lighter: '#EBEBED',
          light: '#A1A1A6',
          dark: '#222224',
          darker: '#1C1C1E',
          darkest: '#0E0E10',
        },
      },
    },
  },
};
