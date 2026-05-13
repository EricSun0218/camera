export default function Page() {
  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', padding: '2rem', maxWidth: 720 }}>
      <h1>Auteur</h1>
      <p>
        Auteur backend. See{' '}
        <a href="https://github.com/EricSun0218/camera">GitHub</a> for the iOS client.
      </p>
      <ul>
        <li><code>POST /api/coach</code></li>
        <li><code>POST /api/grade</code></li>
        <li><code>GET /api/health</code></li>
      </ul>
    </main>
  )
}
