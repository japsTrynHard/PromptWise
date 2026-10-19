-- A trusted guide may legitimately teach several curricular skills. Prevent
-- repeating the same article/topic, rather than excluding the entire article.
DROP INDEX IF EXISTS public.uq_generated_draft_article;
CREATE UNIQUE INDEX uq_generated_draft_article
ON public.generated_content_drafts(article_id, topic_id)
WHERE article_id IS NOT NULL AND status <> 'rejected';
