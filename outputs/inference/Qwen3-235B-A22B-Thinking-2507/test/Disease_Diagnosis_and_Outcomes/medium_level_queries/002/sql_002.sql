WITH ami_patients AS (
  SELECT 
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = a.hadm_id
      AND (
        (d.icd_version = 9 AND d.icd_code LIKE '410%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
      )
  )
  AND p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 62 AND 72
  AND a.dischtime IS NOT NULL
),
exclusion_criteria AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN 
      (icd_version = 9 AND icd_code LIKE '7855%') 
      OR (icd_version = 10 AND icd_code LIKE 'R57%') 
      THEN 1 ELSE 0 END) AS has_shock,
    MAX(CASE WHEN 
      (icd_version = 9 AND icd_code LIKE '5188%') 
      OR (icd_version = 10 AND icd_code LIKE 'J96%') 
      THEN 1 ELSE 0 END) AS has_resp_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
comorbidities AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN 
      (icd_version = 9 AND icd_code LIKE '585%') 
      OR (icd_version = 10 AND icd_code LIKE 'N18%') 
      THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN 
      (icd_version = 9 AND icd_code LIKE '250%') 
      OR (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
      THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
filtered_patients AS (
  SELECT 
    ap.*,
    c.has_ckd,
    c.has_diabetes
  FROM ami_patients ap
  LEFT JOIN comorbidities c ON ap.hadm_id = c.hadm_id
  LEFT JOIN exclusion_criteria ec ON ap.hadm_id = ec.hadm_id
  WHERE COALESCE(ec.has_shock, 0) = 0
    AND COALESCE(ec.has_resp_failure, 0) = 0
),
grouped_data AS (
  SELECT 
    CASE WHEN hospital_los <= 5 THEN 'LOS<=5' ELSE 'LOS>5' END AS los_group,
    COUNT(*) AS n,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(has_ckd) AS ckd_prev,
    AVG(has_diabetes) AS diabetes_prev
  FROM filtered_patients
  GROUP BY los_group
)
SELECT 
  los_group,
  n,
  mortality_rate,
  ckd_prev,
  diabetes_prev
FROM grouped_data

UNION ALL

SELECT 
  'Absolute Difference' AS los_group,
  NULL AS n,
  (SELECT mortality_rate FROM grouped_data WHERE los_group = 'LOS>5') - 
  (SELECT mortality_rate FROM grouped_data WHERE los_group = 'LOS<=5') AS mortality_rate,
  NULL AS ckd_prev,
  NULL AS diabetes_prev

UNION ALL

SELECT 
  'Relative Difference' AS los_group,
  NULL AS n,
  ( (SELECT mortality_rate FROM grouped_data WHERE los_group = 'LOS>5') - 
    (SELECT mortality_rate FROM grouped_data WHERE los_group = 'LOS<=5') 
  ) / 
  NULLIF((SELECT mortality_rate FROM grouped_data WHERE los_group = 'LOS<=5'), 0) AS mortality_rate,
  NULL AS ckd_prev,
  NULL AS diabetes_prev;