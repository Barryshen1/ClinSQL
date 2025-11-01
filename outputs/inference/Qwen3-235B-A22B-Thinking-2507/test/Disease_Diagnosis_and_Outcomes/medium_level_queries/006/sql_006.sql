WITH sepsis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_code LIKE 'A40%' OR 
     (icd_code LIKE 'A41%' AND icd_code != 'A4151') OR 
     icd_code = 'R6520')
),
shock_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('A4151', 'R6521')
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 64 AND 74
    AND a.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
    AND a.hadm_id NOT IN (SELECT hadm_id FROM shock_admissions)
),
comorbidities AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN icd_code IN ('N181','N182','N183','N184','N185','N186','N189','N19') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' 
            OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_with_comorbidities AS (
  SELECT 
    c.*,
    COALESCE(com.has_ckd, 0) AS has_ckd,
    COALESCE(com.has_diabetes, 0) AS has_diabetes,
    NTILE(4) OVER (ORDER BY c.los_days) AS los_quartile
  FROM cohort c
  LEFT JOIN comorbidities com
    ON c.hadm_id = com.hadm_id
)
SELECT 
  los_quartile,
  COUNT(*) AS n,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(has_ckd) AS ckd_prevalence,
  AVG(has_diabetes) AS diabetes_prevalence
FROM cohort_with_comorbidities
GROUP BY los_quartile
ORDER BY los_quartile;