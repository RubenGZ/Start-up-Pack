-- billing.service.sql — eventos de facturación y webhooks

CREATE TABLE billing_events (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id         UUID REFERENCES organizations(id) ON DELETE SET NULL,
  provider       TEXT NOT NULL DEFAULT 'stripe',
  event_type     TEXT NOT NULL,
  provider_event_id TEXT UNIQUE,
  payload        JSONB,
  processed      BOOLEAN NOT NULL DEFAULT FALSE,
  processed_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_billing_events_org ON billing_events(org_id);
CREATE INDEX idx_billing_events_type ON billing_events(event_type);
CREATE INDEX idx_billing_events_processed ON billing_events(processed) WHERE processed = FALSE;

CREATE TABLE invoices (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id            UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  subscription_id   UUID REFERENCES subscriptions(id),
  provider_invoice_id TEXT UNIQUE,
  amount_cents      INTEGER NOT NULL,
  currency          TEXT NOT NULL DEFAULT 'usd',
  status            TEXT NOT NULL CHECK (status IN ('draft','open','paid','void','uncollectible')),
  due_date          TIMESTAMPTZ,
  paid_at           TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invoices_org ON invoices(org_id);
