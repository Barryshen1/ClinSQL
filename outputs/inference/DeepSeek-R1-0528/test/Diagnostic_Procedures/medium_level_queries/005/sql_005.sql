WITH stroke_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_admit,
    -- Identify primary and secondary stroke diagnoses
    MAX(CASE WHEN diag.seq_num = 1 THEN 1 ELSE 0 END) AS is_primary,
    MAX(CASE WHEN diag.seq_num > 1 THEN 1 ELSE 0 END) AS is_secondary
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND ( -- Ischemic stroke codes
      (diag.icd_version = 9 AND diag.icd_code LIKE '433%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '434%')
      OR (diag.icd_version = 9 AND diag.icd_code = '436')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
    )
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 49 AND 59
  GROUP BY adm.subject_id, adm.hadm_id, pat.gender, age_admit
  HAVING is_primary = 1 OR is_secondary = 1 -- Ensure valid stroke diagnosis
),

icu_stay_length AS (
  SELECT
    sa.hadm_id,
    SUM(icu.los) AS total_icu_days
  FROM stroke_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON sa.hadm_id = icu.hadm_id
  GROUP BY sa.hadm_id
  HAVING total_icu_days BETWEEN 1 AND 8 -- Filter to 1-8 day stays
),

diagnostic_procedures AS (
  SELECT
    proc.hadm_id,
    COUNT(DISTINCT proc.seq_num) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` di
    ON proc.icd_code = di.icd_code
    AND proc.icd_version = di.icd_version
  WHERE
    LOWER(di.long_title) LIKE '%diagnostic%'
    OR LOWER(di.long_title) LIKE '%imaging%'
    OR LOWER(di.long_title) LIKE '%scan%'
    OR LOWER(di.long_title) LIKE '%ultrasound%'
    OR LOWER(di.long_title) LIKE '%x-ray%'
    OR LOWER(di.long_title) LIKE '%mri%'
    OR LOWER(di.long_title) LIKE '%ct%'
    OR LOWER(di.long_title) LIKE '%tomography%'
  GROUP BY proc.hadm_id
),

combined_data AS (
  SELECT
    sa.hadm_id,
    sa.age_admit,
    CASE
      WHEN sa.is_primary = 1 THEN 'Primary'
      WHEN sa.is_secondary = 1 THEN 'Secondary'
    END AS diagnosis_type,
    CASE
      WHEN isl.total_icu_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN isl.total_icu_days BETWEEN 5 AND 8 THEN '5-8'
    END AS stay_length_group,
    COALESCE(dp.procedure_count, 0) AS procedure_count
  FROM stroke_admissions sa
  INNER JOIN icu_stay_length isl
    ON sa.hadm_id = isl.hadm_id
  LEFT JOIN diagnostic_procedures dp
    ON sa.hadm_id = dp.hadm_id
)

SELECT
  diagnosis_type,
  stay_length_group,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  COUNT(*) AS num_admissions
FROM combined_data
GROUP BY diagnosis_type, stay_length_group
ORDER BY diagnosis_type, stay_length_group;