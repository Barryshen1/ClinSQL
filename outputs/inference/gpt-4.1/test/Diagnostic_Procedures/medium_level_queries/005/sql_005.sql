WITH ischemic_stroke_admissions AS (
  -- Identify admissions for females 49-59 with ischemic stroke
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age,
    pat.gender,
    diag.seq_num,
    diag.icd_code,
    diag.icd_version,
    icd.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
      ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND (
      -- ICD-10: I63.x (Cerebral infarction)
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
      -- ICD-9: 433.x1, 434.x1 (Cerebral infarction)
      OR (diag.icd_version = 9 AND (diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%'))
      -- Optionally, filter by long_title for extra safety
      OR LOWER(icd.long_title) LIKE '%ischemic stroke%'
      OR LOWER(icd.long_title) LIKE '%cerebral infarction%'
    )
),
admission_stroke_type AS (
  -- For each admission, determine if ischemic stroke is primary or secondary
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    anchor_age,
    gender,
    CASE
      WHEN MIN(seq_num) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM ischemic_stroke_admissions
  GROUP BY subject_id, hadm_id, admittime, dischtime, anchor_age, gender
),
admission_los_group AS (
  -- Calculate LOS and group into 1-4 vs 5-8 days
  SELECT
    *,
    SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) AS los_days,
    CASE
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) BETWEEN 1 AND 4 THEN '1-4'
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_group
  FROM admission_stroke_type
),
diagnostic_procedures AS (
  -- Identify diagnostic procedures per admission
  SELECT
    proc.subject_id,
    proc.hadm_id,
    proc.icd_code,
    proc.icd_version,
    dip.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
      ON proc.icd_code = dip.icd_code AND proc.icd_version = dip.icd_version
  WHERE
    -- Filter for diagnostic procedures by title
    LOWER(dip.long_title) LIKE '%diagnostic%'
    OR LOWER(dip.long_title) LIKE '%imaging%'
    OR LOWER(dip.long_title) LIKE '%ct%'
    OR LOWER(dip.long_title) LIKE '%mri%'
    OR LOWER(dip.long_title) LIKE '%ultrasound%'
    OR LOWER(dip.long_title) LIKE '%x-ray%'
    OR LOWER(dip.long_title) LIKE '%eeg%'
    OR LOWER(dip.long_title) LIKE '%angiography%'
),
admission_diag_proc_count AS (
  -- Count diagnostic procedures per admission
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.los_group,
    adm.diagnosis_type,
    COUNT(DISTINCT dp.icd_code) AS diagnostic_procedure_count
  FROM admission_los_group adm
    LEFT JOIN diagnostic_procedures dp
      ON adm.hadm_id = dp.hadm_id
  WHERE adm.los_group IS NOT NULL
  GROUP BY adm.subject_id, adm.hadm_id, adm.los_group, adm.diagnosis_type
)
-- Final aggregation: mean, min, max diagnostic procedures per admission by group
SELECT
  los_group,
  diagnosis_type,
  AVG(diagnostic_procedure_count) AS mean_diagnostic_procedures,
  MIN(diagnostic_procedure_count) AS min_diagnostic_procedures,
  MAX(diagnostic_procedure_count) AS max_diagnostic_procedures,
  COUNT(*) AS admission_count
FROM admission_diag_proc_count
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;