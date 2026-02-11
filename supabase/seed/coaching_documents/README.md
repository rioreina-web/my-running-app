# Coaching Documents

This folder contains the knowledge base for the AI running coach. Each document is ingested into the database with vector embeddings for semantic search.

## Document Format

Each document should be a JSON file with the following structure:

```json
{
  "title": "Document Title",
  "content": "The full text content of the document...",
  "category": "recovery",
  "metadata": {
    "source": "optional source reference",
    "tags": ["optional", "tags"]
  }
}
```

## Categories

- `rest` - Rest days, sleep, deload weeks
- `recovery` - Active recovery, foam rolling, stretching
- `mindset` - Mental training, motivation, race nerves
- `training` - Periodization, progressive overload, workout types
- `injury` - Prevention, warning signs, common injuries
- `nutrition` - Fueling, hydration, recovery nutrition

## Ingesting Documents

Use the `ingest-documents` edge function to add documents:

```bash
curl -X POST "https://aqdijapxmjqaetursrde.supabase.co/functions/v1/ingest-documents" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "documents": [
      {
        "title": "Your Title",
        "content": "Your content...",
        "category": "recovery"
      }
    ]
  }'
```

## Sample Documents

See the `samples/` folder for example documents you can use as templates.
