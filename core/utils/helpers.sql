-- helpers.sql — funciones utilitarias compartidas

-- Genera slug único a partir de texto
CREATE OR REPLACE FUNCTION slugify(input TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN LOWER(REGEXP_REPLACE(TRIM(input), '[^a-zA-Z0-9]+', '-', 'g'));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Verifica si org tiene plan activo
CREATE OR REPLACE FUNCTION org_has_active_plan(p_org_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM subscriptions
    WHERE org_id = p_org_id
      AND status = 'active'
      AND (current_period_end IS NULL OR current_period_end > NOW())
  );
END;
$$ LANGUAGE plpgsql;

-- Soft delete genérico via is_active
CREATE OR REPLACE FUNCTION soft_delete(p_table TEXT, p_id UUID)
RETURNS void AS $$
BEGIN
  EXECUTE FORMAT('UPDATE %I SET is_active = FALSE, updated_at = NOW() WHERE id = $1', p_table)
  USING p_id;
END;
$$ LANGUAGE plpgsql;
