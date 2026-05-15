export default function Page() {
  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', padding: '2rem', maxWidth: 720 }}>
      <h1>Cue</h1>
      <p>
        Cue backend. See{' '}
        <a href="https://github.com/EricSun0218/cue">GitHub</a> for the iOS client.
      </p>
      <ul>
        <li><code>POST /api/guidance</code></li>
        <li><code>POST /api/grade</code></li>
        <li><code>GET /api/health</code></li>
      </ul>
    </main>
  )
}
