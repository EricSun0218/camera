import { Hono } from 'hono'

type Bindings = {
  ANTHROPIC_API_KEY: string
  RATELIMIT: KVNamespace
}

const app = new Hono<{ Bindings: Bindings }>()

app.get('/', (c) => c.text('Auteur backend'))

export default app
