with `d_icd_diagnoses` to get the diagnosis descriptions and apply conditional logic based on known Elixhauser categories using keywords or known ICD code ranges.
- However, for accuracy and simplicity, a better alternative is to use a well-established method: predefine ICD code lists for Elixhauser comorbidities as per published implementations (e.g., Quan et al.). Since we cannot reference a precomputed table, we embed a minimal set of ICD code patterns for common Elixhauser conditions using `icd_code` matching logic.
- We define a scalar mapping for key Elixhauser conditions using `icd_code` and `icd_version` from `d_icd_diagnoses`. This avoids the need for the inaccessible `elixhauser_quan` table.
- Additionally, the original query only checks for the existence of *any* procedure, not specifically *postoperative* complications. However, the term "postoperative complications" is ambiguous without a clear definition. Given the context and lack of explicit complication codes, we interpret this as patients who had a procedure during the admission — which the original query already checks via `procedures_icd`. We retain this logic but clarify it.
- We move the `d_icd_diagnoses` join into the comorbidity calculation and use conditional aggregation based on known ICD code prefixes for Elixhauser conditions.

Key changes:
1. Remove dependency on `mimiciv_3_1_concepts.elixhauser_quan`.
2. Join `diagnoses_icd` with `d_icd_diagnoses` to get diagnosis descriptions and use pattern matching on ICD codes to identify Elixhauser comorbidities.
3. Use `icd_version` to correctly interpret ICD-9 vs ICD-10 codes.
4. Implement a simplified but valid Elixhauser count using known code ranges (based on standard mappings).
5. Keep all other logic (age filter, ICU flag, LOS grouping) intact.

sql
WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1), DAY) / 365.25 + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
cohort AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    pa.age_at_admission
  FROM patient_admissions pa
  WHERE pa.age_at_admission >= 82 AND pa.age_at_admission <= 92
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      WHERE p.hadm_id = pa.hadm_id
    )
),
-- Map ICD codes to Elixhauser comorbidities using known code patterns (Quan et al.)
comorbidity_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- Congestive heart failure
    MAX(CASE
      WHEN di.icd_version = 9 AND di.icd_code LIKE '428%' THEN 1
      WHEN di.icd_version = 10 AND di.icd_code LIKE 'I50%' THEN 1
      ELSE 0 END) AS congestive_heart_failure,
    -- Cardiac arrhythmias
    MAX(CASE
      WHEN di.icd_version = 9 AND di.icd_code IN ('4260', '4267', '4269', '4270', '4272', '4273', '4276', '4278', '4279') THEN 1
      WHEN di.icd_version = 10 AND di.icd_code LIKE 'I44%' OR di.icd_code LIKE 'I45%' OR di.icd_code LIKE 'I47%' OR di.icd_code LIKE 'I48%' OR di.icd_code LIKE 'I49%' THEN 1
      ELSE 0 END) AS cardiac_arrhythmias,
    -- Valvular disease
    MAX(CASE
      WHEN di.icd_version = 9 AND di.icd_code IN ('09320', '09324', '394%', '395%', '396%', '397%', '7463', '7464', '7465', '7466') THEN 1
      WHEN di.icd_version = 10 AND (di.icd_code LIKE 'I05%' OR di.icd_code LIKE 'I06%' OR di.icd_code LIKE 'I07%' OR di.icd_code LIKE 'I08%' OR di.icd_code LIKE 'I34%' OR di.icd_code LIKE 'I35%' OR di.icd_code LIKE 'I36%' OR di.icd_code LIKE 'I37%' OR di.icd_code LIKE 'I38%' OR di.icd_code LIKE 'I39%') THEN 1
      ELSE 0 END) AS valvular_disease,
    -- Pulmonary circulation
    MAX(CASE
      WHEN di.icd_version = 9 AND di.icd_code IN ('4151', '416%', '4179') THEN 1
      WHEN di.icd_version = 10 AND (di.icd_code LIKE 'I26%' OR di.icd_code LIKE 'I27%') THEN 1
      ELSE 0 END) AS pulmonary_circulation,
    -- Peripheral vascular
    MAX(CASE
      WHEN di.icd_version = 9 AND di.icd_code IN ('0930', '440%', '441%', '4471') THEN 1
      WHEN di.icd_version = 10 AND (di.icd_code LIKE 'I70%' OR di.icd_code LIKE 'I71%' OR di.icd_code LIKE 'I73%' OR di.icd_code LIKE 'I74%' OR di.icd_code LIKE 'I77%') THEN 1
      ELSE 0 END) AS peripheral_vascular,
    -- Hypertension
    MAX(CASE
      WHEN di.icd_version = 9 AND di.icd_code IN ('401%', '402%', '403%', '404%', '405%') THEN 1
      WHEN di.icd_version = 10 AND (di.icd_code LIKE 'I10%' OR di.icd_code LIKE 'I11%' OR di.icd_code LIKE 'I12%' OR di.icd_code LIKE 'I13%' OR di.icd_code LIKE 'I15%') THEN 1
      ELSE 0 END) AS hypertension,
    -- Paralysis
    MAX(CASE
      WHEN di.icd_version = 9 AND di.icd_code IN ('3341', '342%', '343%', '3440', '3441', '3442', '3443', '3444', '3445', '3446', '3448', '3449') THEN 1
      WHEN di.icd_version = 10 AND (di.icd_code LIKE 'G81%' OR di.icd_code LIKE 'G82%' OR di.icd_code LIKE 'G83%') THEN 1
      ELSE 0 END) AS paralysis,
    -- Other neurological
    MAX(CASE
      WHEN di.icd_version = 9 AND di.icd_code IN ('3319', '332%', '3334', '3335', '334%', '340%') THEN 1
      WHEN di.icd_version = 10 AND (di.icd_code LIKE 'G20%' OR di.icd_code LIKE 'G21%' OR di.icd_code LIKE 'G22%' OR di.icd_code LIKE 'G31%' OR di.icd_code LIKE 'G35%' OR di.icd_code LIKE 'G;