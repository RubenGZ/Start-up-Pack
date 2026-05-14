-- patients_seed.sql — HealthStack_Pro: 50 pacientes ficticios encriptados [SUP-24]
-- Usa pgp_sym_encrypt() de pgcrypto (instalado en 0001_init)
-- DEMO ONLY — en producción: key desde variable de entorno, nunca hardcoded

-- 1. Tabla de pacientes (datos identificativos encriptados)
CREATE TABLE IF NOT EXISTS patients (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id      UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name_enc    BYTEA NOT NULL,     -- pgp_sym_encrypt(nombre completo, key)
  dob_enc     BYTEA NOT NULL,     -- pgp_sym_encrypt(fecha nacimiento ISO, key)
  blood_type  TEXT CHECK (blood_type IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  nhc         TEXT UNIQUE,        -- Número Historia Clínica — no sensible
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Tabla de historial médico (todo encriptado)
CREATE TABLE IF NOT EXISTS medical_records (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  patient_id     UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  diagnosis_enc  BYTEA NOT NULL,  -- pgp_sym_encrypt(diagnóstico, key)
  medications    BYTEA,           -- pgp_sym_encrypt(JSON array medicación, key)
  allergies_enc  BYTEA,           -- pgp_sym_encrypt(alergias, key)
  notes_enc      BYTEA,           -- pgp_sym_encrypt(notas clínicas, key)
  recorded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_patients_org    ON patients(org_id);
CREATE INDEX IF NOT EXISTS idx_patients_nhc    ON patients(nhc);
CREATE INDEX IF NOT EXISTS idx_records_patient ON medical_records(patient_id);

-- 3. Función auxiliar de desencriptado (requiere key)
CREATE OR REPLACE FUNCTION get_patient_record(p_patient_id UUID, p_key TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_p patients; v_r medical_records;
BEGIN
  SELECT * INTO v_p FROM patients WHERE id = p_patient_id AND is_active = TRUE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
  SELECT * INTO v_r FROM medical_records WHERE patient_id = p_patient_id
    ORDER BY recorded_at DESC LIMIT 1;
  RETURN jsonb_build_object(
    'nhc',        v_p.nhc,
    'blood_type', v_p.blood_type,
    'name',       pgp_sym_decrypt(v_p.name_enc, p_key),
    'dob',        pgp_sym_decrypt(v_p.dob_enc,  p_key),
    'diagnosis',  pgp_sym_decrypt(v_r.diagnosis_enc, p_key),
    'medications',pgp_sym_decrypt(v_r.medications,   p_key),
    'allergies',  pgp_sym_decrypt(v_r.allergies_enc, p_key),
    'notes',      pgp_sym_decrypt(v_r.notes_enc,     p_key)
  );
END;
$$;

-- 4. Seed: 50 pacientes demo con historiales encriptados
DO $$
DECLARE
  v_org  UUID := '00000000-0000-0000-0000-000000000001';
  v_key  TEXT := 'DEMO_KEY_healthstack_CHANGE_IN_PROD';
  v_pid  UUID;
  names  TEXT[] := ARRAY[
    'María García López','Carlos Rodríguez Martín','Ana Fernández Sánchez',
    'Luis González Pérez','Isabel Martínez Torres','Pablo Sánchez Ruiz',
    'Carmen López García','Miguel Hernández Díaz','Elena Torres Moreno',
    'David Ramírez Jiménez','Sofía Álvarez Castro','Javier Moreno Romero',
    'Laura Gutiérrez Navarro','Antonio Jiménez Molina','Rosa Serrano Blanco',
    'Fernando Blanco Ortega','Cristina Navarro Reyes','Óscar Reyes Vargas',
    'Silvia Vargas Ortiz','Roberto Ortiz Medina','Natalia Medina Castillo',
    'Eduardo Castillo Herrera','Patricia Herrera Fuentes','Ricardo Fuentes León',
    'Marta León Iglesias','Alejandro Iglesias Santos','Raquel Santos Aguilar',
    'Sergio Aguilar Vega','Alicia Vega Mora','Diego Mora Delgado',
    'Virginia Delgado Cano','Rubén Cano Pascual','Beatriz Pascual Nieto',
    'Marcos Nieto Guerrero','Lucía Guerrero Campos','Andrés Campos Ramos',
    'Nuria Ramos Vidal','Jorge Vidal Pons','Claudia Pons Ferrer',
    'Enrique Ferrer Soler','Pilar Soler Fuster','Iván Fuster Mas',
    'Amparo Mas Nadal','Víctor Nadal Coll','Teresa Coll Puig',
    'Gonzalo Puig Esteve','Mónica Esteve Peris','Héctor Peris Montes',
    'Verónica Montes Giménez','Rafael Giménez Roig'
  ];
  diags  TEXT[] := ARRAY[
    'Hipertensión arterial','Diabetes mellitus tipo 2','Asma bronquial',
    'Hipotiroidismo','Artrosis lumbar','Fibromialgia','EPOC',
    'Insuficiencia cardíaca','Ansiedad generalizada','Depresión mayor',
    'Migraña crónica','Artritis reumatoide','Enfermedad de Crohn',
    'Gastritis crónica','Síndrome de intestino irritable','Psoriasis',
    'Celiaquía','Anemia ferropénica','Hiperlipidemia mixta','Gota'
  ];
  meds   TEXT[] := ARRAY[
    '["Enalapril 10mg","Amlodipino 5mg"]',
    '["Metformina 850mg","Sitagliptina 100mg"]',
    '["Salbutamol inhalador","Budesonida 200mcg"]',
    '["Levotiroxina 50mcg"]',
    '["Ibuprofeno 600mg","Omeprazol 20mg"]',
    '["Pregabalina 75mg","Duloxetina 60mg"]',
    '["Tiotropio 18mcg","Salmeterol 50mcg"]',
    '["Furosemida 40mg","Espironolactona 25mg"]',
    '["Sertralina 50mg","Alprazolam 0.25mg"]',
    '["Venlafaxina 150mg","Mirtazapina 15mg"]'
  ];
  alrgs  TEXT[] := ARRAY[
    'Penicilina','AINE','Sulfamidas','Ninguna conocida',
    'Látex','Polen estacional','Ácaros del polvo','Mariscos','Aspirina','Yodo'
  ];
  btype  TEXT[] := ARRAY['A+','A-','B+','B-','AB+','AB-','O+','O-'];
BEGIN
  FOR i IN 1..50 LOOP
    INSERT INTO patients (org_id, name_enc, dob_enc, blood_type, nhc)
    VALUES (
      v_org,
      pgp_sym_encrypt(names[(i-1) % 50 + 1], v_key),
      pgp_sym_encrypt((DATE '1950-01-01' + ((i*127+31) % 18000))::TEXT, v_key),
      btype[(i-1) % 8 + 1],
      format('NHC-%05s', i)
    )
    RETURNING id INTO v_pid;

    INSERT INTO medical_records (patient_id, diagnosis_enc, medications, allergies_enc, notes_enc)
    VALUES (
      v_pid,
      pgp_sym_encrypt(diags[(i-1) % 20 + 1], v_key),
      pgp_sym_encrypt(meds[ (i-1) % 10 + 1], v_key),
      pgp_sym_encrypt(alrgs[(i-1) % 10 + 1], v_key),
      pgp_sym_encrypt(format(
        'Paciente %s. Primera consulta. Control en %s meses. Sin incidencias agudas.',
        names[(i-1) % 50 + 1], (i % 6) + 1
      ), v_key)
    );
  END LOOP;
  RAISE NOTICE '[HealthStack] 50 pacientes demo OK — key DEMO, cambiar en producción';
END $$;

COMMENT ON TABLE patients IS
  'Pacientes HealthStack. name_enc y dob_enc encriptados con pgp_sym_encrypt. Key en variable de entorno.';
COMMENT ON TABLE medical_records IS
  'Historial médico encriptado por paciente. Desencriptar con get_patient_record(id, key).';
