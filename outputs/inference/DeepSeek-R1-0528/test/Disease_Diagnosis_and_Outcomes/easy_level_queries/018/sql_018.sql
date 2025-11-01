WITH stroke_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate exact age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.subject_id = diag.subject_id
    AND a.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'M'
    AND diag.seq_num = 1  -- Primary diagnosis only
    AND (
      -- ICD-10 codes for hemorrhagic stroke
      (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^I6[0-2]')) 
      OR
      -- ICD-9 codes for hemorrhagic stroke
      (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^(430|431|432)'))
    )
    AND a.dischtime > a.admittime  -- Exclude invalid stays
)
SELECT
  STDDEV_POP(
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0
  ) AS los_stddev_days
FROM stroke_admissions
WHERE age_at_admit BETWEEN 45 AND 55;  -- Target age group;