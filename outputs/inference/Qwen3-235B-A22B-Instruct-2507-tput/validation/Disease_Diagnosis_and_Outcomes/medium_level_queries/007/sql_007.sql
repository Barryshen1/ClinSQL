WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 51 AND 61
),
heart_failure AS (
  SELECT DISTINCT pa.*
  FROM patients_age pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
     OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
),
-- Define Elixhauser comorbidities (excluding heart failure)
comorbidities AS (
  SELECT
    di.hadm_id,
    SUM(CASE
      -- Cardiac arrhythmias
      WHEN (di.icd_version = 10 AND di.icd_code LIKE 'I44%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I45%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I47%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I48%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I49%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '426%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '427%') THEN 1
      ELSE 0
    END) AS cardiac_arrhythmias,
    SUM(CASE
      -- Valvular disease
      WHEN (di.icd_version = 10 AND di.icd_code LIKE 'I05%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I06%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I07%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I08%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I34%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I35%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I36%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I37%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I38%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I39%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '394%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '395%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '396%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '397%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '424%') THEN 1
      ELSE 0
    END) AS valvular_disease,
    SUM(CASE
      -- Pulmonary circulation disorders
      WHEN (di.icd_version = 10 AND di.icd_code LIKE 'I26%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I27%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I28%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '415%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '416%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '417%') THEN 1
      ELSE 0
    END) AS pulmonary_circulation,
    SUM(CASE
      -- Peripheral vascular disease
      WHEN (di.icd_version = 10 AND di.icd_code LIKE 'I70%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I71%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I73%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I74%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I77%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I78%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I79%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '440%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '441%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '443%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '444%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '447%') THEN 1
      ELSE 0
    END) AS peripheral_vascular,
    SUM(CASE
      -- Hypertension
      WHEN (di.icd_version = 10 AND di.icd_code LIKE 'I10%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I11%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I12%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I13%') OR
           (di.icd_version = 10 AND di.icd_code LIKE 'I15%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '401%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '402%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '403%') OR
           (di.icd_version = 9 AND di.icd_code LIKE '404%;