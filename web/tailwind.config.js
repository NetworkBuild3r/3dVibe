/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["IBM Plex Sans", "ui-sans-serif", "system-ui"],
        display: ["Sora", "IBM Plex Sans", "ui-sans-serif"]
      },
      colors: {
        ink: {
          950: "#0b0f14",
          900: "#121821",
          800: "#1a2330",
          700: "#243044"
        },
        accent: {
          400: "#5eead4",
          500: "#2dd4bf",
          600: "#14b8a6"
        }
      }
    }
  },
  plugins: []
};
