WITH base_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
hf_admissions AS (
  SELECT DISTINCT ba.*
  FROM base_admissions ba
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = ba.hadm_id
      AND (
        (d.icd_version = 9 AND d.icd_code LIKE '428%') 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
      )
  )
),
cohort AS (
  SELECT 
    ha.subject_id,
    ha.hadm_id,
    ha.hospital_expire_flag,
    ha.gender,
    ha.anchor_age,
    ha.los_days,
    COUNT(d.icd_code) AS num_diagnoses
  FROM hf_admissions ha
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON ha.hadm_id = d.hadm_id
  GROUP BY 
    ha.subject_id, ha.hadm_id, ha.hospital_expire_flag, 
    ha.gender, ha.anchor_age, ha.los_days
),
stratified AS (
  SELECT 
    c.*,
    NTILE(4) OVER (ORDER BY c.los_days ASC) AS los_quartile,
    NTILE(3) OVER (ORDER BY c.num_diagnoses ASC) AS comorb_tertile
  FROM cohort c
  WHERE c.los_days > 0
)
SELECT 
  CASE 
    WHEN los_quartile = 1 THEN 'Q1'
    WHEN los_quartile = 2 THEN 'Q2'
    WHEN los_quartile = 3 THEN 'Q3'
    ELSE 'Q4'
  END AS los_quartile,
  CASE 
    WHEN comorb_tertile = 1 THEN 'low'
    WHEN comorb_tertile = 2 THEN 'medium'
    ELSE 'high'
  END AS comorbidity_burden,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct
FROM stratified
GROUP BY los_quartile, comorb_tertile
ORDER BY los_quartile, comorb_tertile;