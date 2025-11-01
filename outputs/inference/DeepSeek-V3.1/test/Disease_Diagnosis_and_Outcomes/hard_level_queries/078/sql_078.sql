WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.deathtime, 
    adm.hospital_expire_flag,
    pt.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 59 AND 69
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE (
        (icd_version = 10 AND icd_code LIKE 'I50%') 
        OR (icd_version = 9 AND icd_code LIKE '428%')
      )
    )
),

aki AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 10 AND icd_code LIKE 'N17%')
    OR (icd_version = 9 AND icd_code LIKE '584%')
  )
),

ards AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 10 AND icd_code = 'J80')
    OR (icd_version = 9 AND icd_code = '518.82')
  )
),

comorbidities AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN (
      (icd_version = 10 AND icd_code LIKE 'I1%') 
      OR (icd_version = 9 AND icd_code BETWEEN '401' AND '405')
    ) THEN 1 ELSE 0 END) AS hypertension,
    MAX(CASE WHEN (
      (icd_version = 10 AND icd_code LIKE 'E1%') 
      OR (icd_version = 9 AND icd_code LIKE '250%')
    ) THEN 1 ELSE 0 END) AS diabetes,
    MAX(CASE WHEN (
      (icd_version = 10 AND icd_code LIKE 'N18%') 
      OR (icd_version = 9 AND icd_code LIKE '585%')
    ) THEN 1 ELSE 0 END) AS ckd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

cohort_with_comorbidities AS (
  SELECT 
    c.*,
    COALESCE(com.hypertension, 0) AS hypertension,
    COALESCE(com.diabetes, 0) AS diabetes,
    COALESCE(com.ckd, 0) AS ckd,
    CASE WHEN c.anchor_age >= 65 THEN 1 ELSE 0 END AS age_score,
    (COALESCE(com.hypertension, 0) + COALESCE(com.diabetes, 0) + 
     COALESCE(com.ckd, 0) + CASE WHEN c.anchor_age >= 65 THEN 1 ELSE 0 END) AS risk_score,
    CASE WHEN c.hospital_expire_flag = 1 
         THEN DATE_DIFF(c.deathtime, c.admittime, DAY) 
         ELSE NULL END AS survival_days
  FROM cohort c
  LEFT JOIN comorbidities com
    ON c.hadm_id = com.hadm_id
)

SELECT
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS in_hospital_deaths,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_percent,
  COUNT(DISTINCT aki.hadm_id) AS aki_cases,
  ROUND(100 * COUNT(DISTINCT aki.hadm_id) / COUNT(*), 2) AS aki_rate_percent,
  COUNT(DISTINCT ards.hadm_id) AS ards_cases,
  ROUND(100 * COUNT(DISTINCT ards.hadm_id) / COUNT(*), 2) AS ards_rate_percent,
  PERCENTILE_CONT(survival_days, 0.5) OVER() AS median_survival_days,
  MIN(risk_score) AS min_score,
  PERCENTILE_CONT(risk_score, 0.25) OVER() AS p25_score,
  PERCENTILE_CONT(risk_score, 0.5) OVER() AS median_score,
  PERCENTILE_CONT(risk_score, 0.75) OVER() AS p75_score,
  PERCENTILE_CONT(risk_score, 0.9) OVER() AS p90_score,
  MAX(risk_score) AS max_score
FROM cohort_with_comorbidities c
LEFT JOIN aki ON c.hadm_id = aki.hadm_id
LEFT JOIN ards ON c.hadm_id = ards.hadm_id;