import type { ReactNode } from 'react'

export const metadata = {
  title: 'Cue',
  description: 'Cue backend on Vercel.',
}

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
