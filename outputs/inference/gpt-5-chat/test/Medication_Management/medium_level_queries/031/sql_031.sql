WITH base_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
),
dx_flags AS (
  SELECT hadm.subject_id, hadm.hadm_id,
         MAX(CASE WHEN (
             (d.icd_version = 9 AND SUBSTR(d.icd_code,1,3) IN ('249','250')) OR
             (d.icd_version = 10 AND SUBSTR(d.icd_code,1,3) IN ('E10','E11','E13','E14'))
           )
         THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE WHEN (
             (d.icd_version = 9 AND SUBSTR(d.icd_code,1,3) = '428') OR
             (d.icd_version = 10 AND SUBSTR(d.icd_code,1,3) = 'I50')
           )
         THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN base_cohort hadm
    ON d.subject_id = hadm.subject_id
    AND d.hadm_id = hadm.hadm_id
  GROUP BY hadm.subject_id, hadm.hadm_id
),
cohort AS (
  SELECT b.subject_id, b.hadm_id, b.admittime, b.dischtime
  FROM base_cohort b
  JOIN dx_flags dx
    ON b.subject_id = dx.subject_id
    AND b.hadm_id = dx.hadm_id
  WHERE dx.has_diabetes = 1
    AND dx.has_hf = 1
),
glp1_prescriptions AS (
  SELECT subject_id, hadm_id,
         MIN(starttime) AS first_starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE REGEXP_CONTAINS(LOWER(drug), r'(exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide)')
    AND starttime IS NOT NULL
  GROUP BY subject_id, hadm_id
),
classified AS (
  SELECT c.subject_id, c.hadm_id,
         CASE WHEN g.first_starttime <= c.admittime + INTERVAL 24 HOUR THEN 1 ELSE 0 END AS early_flag,
         CASE WHEN g.first_starttime >= c.dischtime - INTERVAL 12 HOUR THEN 1 ELSE 0 END AS late_flag
  FROM cohort c
  LEFT JOIN glp1_prescriptions g
    ON c.subject_id = g.subject_id
    AND c.hadm_id = g.hadm_id
)
SELECT
  COUNT(DISTINCT subject_id) AS total_patients,
  COUNT(DISTINCT CASE WHEN early_flag = 1 THEN subject_id END) AS early_count,
  COUNT(DISTINCT CASE WHEN late_flag = 1 THEN subject_id END) AS late_count,
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN early_flag = 1 THEN subject_id END),
              COUNT(DISTINCT subject_id)) * 100 AS early_pct,
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN late_flag = 1 THEN subject_id END),
              COUNT(DISTINCT subject_id)) * 100 AS late_pct
FROM classified;