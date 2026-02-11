-- Add transcript_url column to store full transcription file
ALTER TABLE public.training_logs
ADD COLUMN IF NOT EXISTS transcript_url TEXT;

COMMENT ON COLUMN public.training_logs.transcript_url IS
'URL to the full raw transcript file stored in training-memos bucket';
