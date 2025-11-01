WITH aki_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND di.seq_num = 1
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '584%')
      OR
      (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_stats AS (
  SELECT
    PERCENTILE_CONT(los_days, 0.25) OVER() AS q1,
    PERCENTILE_CONT(los_days, 0.75) OVER() AS q3
  FROM aki_admissions
)
SELECT
  DISTINCT
  ROUND(q3 - q1, 2) AS iqr_los_days
FROM los_stats;