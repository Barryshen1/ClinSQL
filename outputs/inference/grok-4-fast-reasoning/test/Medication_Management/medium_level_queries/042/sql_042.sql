WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 51 AND 61
    AND a.admission_type != 'OBSERVATION'
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_version = 10 AND icd_code LIKE 'E1[0-3]%')
         OR (icd_version = 9 AND icd_code LIKE '250.%')
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_version = 10 AND (
        icd_code LIKE 'I50.1%' OR
        icd_code LIKE 'I50.2%' OR
        icd_code LIKE 'I50.3%'
      ))
         OR (icd_version = 9 AND icd_code LIKE '428%')
    )
),
med_status AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- Insulin early
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = c.hadm_id
        AND p.drug IS NOT NULL
        AND LOWER(p.drug) LIKE '%insulin%'
        AND p.starttime < c.admittime + INTERVAL 2 DAY
        AND (p.stoptime IS NULL OR p.stoptime > c.admittime)
    ) THEN 1 ELSE 0 END AS on_insulin_early,
    -- Oral early
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = c.hadm_id
        AND p.drug IS NOT NULL
        AND (
          LOWER(p.drug) LIKE '%metformin%' OR
          LOWER(p.drug) LIKE '%glipizide%' OR
          LOWER(p.drug) LIKE '%glyburide%' OR
          LOWER(p.drug) LIKE '%glimepiride%' OR
          LOWER(p.drug) LIKE '%pioglitazone%' OR
          LOWER(p.drug) LIKE '%sitagliptin%' OR
          LOWER(p.drug) LIKE '%linagliptin%' OR
          LOWER(p.drug) LIKE '%empagliflozin%' OR
          LOWER(p.drug) LIKE '%dapagliflozin%' OR
          LOWER(p.drug) LIKE '%canagliflozin%' OR
          LOWER(p.drug) LIKE '%acarbose%' OR
          LOWER(p.drug) LIKE '%repaglinide%' OR
          LOWER(p.drug) LIKE '%nateglinide%' OR
          LOWER(p.drug) LIKE '%saxagliptin%' OR
          LOWER(p.drug) LIKE '%alogliptin%' OR
          LOWER(p.drug) LIKE '%ertugliflozin%' OR
          LOWER(p.drug) LIKE '%miglitol%'
        )
        AND p.starttime < c.admittime + INTERVAL 2 DAY
        AND (p.stoptime IS NULL OR p.stoptime > c.admittime)
    ) THEN 1 ELSE 0 END AS on_oral_early,
    -- Insulin late
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = c.hadm_id
        AND p.drug IS NOT NULL
        AND LOWER(p.drug) LIKE '%insulin%'
        AND p.starttime < c.dischtime
        AND (p.stoptime IS NULL OR p.stoptime > c.dischtime - INTERVAL 1 DAY)
    ) THEN 1 ELSE 0 END AS on_insulin_late,
    -- Oral late
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE p.hadm_id = c.hadm_id
        AND p.drug IS NOT NULL
        AND (
          LOWER(p.drug) LIKE '%metformin%' OR
          LOWER(p.drug) LIKE '%glipizide%' OR
          LOWER(p.drug) LIKE '%glyburide%' OR
          LOWER(p.drug) LIKE '%glimepiride%' OR
          LOWER(p.drug) LIKE '%pioglitazone%' OR
          LOWER(p.drug) LIKE '%sitagliptin%' OR
          LOWER(p.drug) LIKE '%linagliptin%' OR
          LOWER(p.drug) LIKE '%empagliflozin%' OR
          LOWER(p.drug) LIKE '%dapagliflozin%' OR
          LOWER(p.drug) LIKE '%canagliflozin%' OR
          LOWER(p.drug) LIKE '%acarbose%' OR
          LOWER(p.drug) LIKE '%repaglinide%' OR
          LOWER(p.drug) LIKE '%nateglinide%' OR
          LOWER(p.drug) LIKE '%saxagliptin%' OR
          LOWER(p.drug) LIKE '%alogliptin%' OR
          LOWER(p.drug) LIKE '%ertugliflozin%' OR
          LOWER(p.drug) LIKE '%miglitol%'
        )
        AND p.starttime < c.dischtime
        AND (p.stoptime IS NULL OR p.stoptime > c.dischtime - INTERVAL 1 DAY)
    ) THEN 1 ELSE 0 END AS on_oral_late
  FROM cohort c
)
SELECT
  COUNT(*) AS total_patients,
  -- Percents first 48h
  ROUND(100.0 * AVG(on_insulin_early), 2) AS pct_insulin_first_48h,
  ROUND(100.0 * AVG(on_oral_early), 2) AS pct_oral_first_48h,
  -- Percents final 24h
  ROUND(100.0 * AVG(on_insulin_late), 2) AS pct_insulin_final_24h,
  ROUND(100.0 * AVG(on_oral_late), 2) AS pct_oral_final_24h,
  -- Insulin counts
  SUM(on_insulin_early * on_insulin_late) AS continued_insulin_count,
  SUM((1 - on_insulin_early) * on_insulin_late) AS initiated_insulin_count,
  SUM(on_insulin_early * (1 - on_insulin_late)) AS discontinued_insulin_count,
  -- Oral counts
  SUM(on_oral_early * on_oral_late) AS continued_oral_count,
  SUM((1 - on_oral_early) * on_oral_late) AS initiated_oral_count,
  SUM(on_oral_early * (1 - on_oral_late)) AS discontinued_oral_count
FROM med_status;