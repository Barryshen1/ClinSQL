WITH primary_aki AS (
  -- admissions with a primary diagnosis of acute kidney injury (ICD-9 584* or ICD-10 N17*)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.seq_num = 1
    AND (
      (d.icd_version = 9  AND d.icd_code LIKE '584%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
    )
),
cohort AS (
  -- join admissions -> primary AKI -> patients, compute LOS in days
  SELECT
    a.hadm_id,
    a.subject_id,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 60.0 * 24.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN primary_aki p
    ON a.hadm_id = p.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON a.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
    AND pt.anchor_age BETWEEN 81 AND 91
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
),
stats AS (
  SELECT
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM cohort
)
SELECT
  n_admissions,
  quantiles[OFFSET(25)] AS q25_days,
  quantiles[OFFSET(75)] AS q75_days,
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_days
FROM stats;