WITH hadm_dx AS (
  -- For each hospital admission, set flags if any diagnosis looks like ischemic heart disease/ACS and if any looks like COPD
  SELECT
    diag.hadm_id,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(d.long_title),
         r'(ischemic|myocardial infarction|acute coronary|angina|coronary)') THEN 1 ELSE 0 END) AS ischemic_flag,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(d.long_title),
         r'(chronic obstructive|copd|chronic bronchitis|emphysema)') THEN 1 ELSE 0 END) AS copd_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
   AND diag.icd_version = d.icd_version
  GROUP BY diag.hadm_id
)

SELECT
  -- 75th percentile of LOS in days (approximate) and count of admissions used
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  COUNT(*) AS n_admissions
FROM (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN hadm_dx h
    ON a.hadm_id = h.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND h.ischemic_flag = 1
    AND h.copd_flag = 1
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
);