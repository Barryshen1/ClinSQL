WITH patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 77 AND 87
),
hf_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
has_ckd AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '585%' OR icd_code LIKE '586%'))
     OR (icd_version = 10 AND icd_code LIKE 'N18%')
),
has_dm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR 
                                 icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR 
                                 icd_code LIKE 'E14%'))
),
first_icu AS (
  SELECT hadm_id, MIN(intime) AS first_icu_time
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
base AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_cat,
    CASE 
      WHEN fi.first_icu_time IS NOT NULL 
           AND fi.first_icu_time <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY) 
      THEN 'ICU' 
      ELSE 'non-ICU' 
    END AS day1_icu,
    CASE WHEN ck.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
    CASE WHEN dm.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_dm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients p ON a.subject_id = p.subject_id
  INNER JOIN hf_admissions hf ON a.hadm_id = hf.hadm_id
  LEFT JOIN first_icu fi ON a.hadm_id = fi.hadm_id
  LEFT JOIN has_ckd ck ON a.hadm_id = ck.hadm_id
  LEFT JOIN has_dm dm ON a.hadm_id = dm.hadm_id
  WHERE a.dischtime IS NOT NULL
)
SELECT 
  day1_icu,
  los_cat,
  COUNT(*) AS n,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_pct,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_dm) * 100, 2) AS diabetes_prevalence_pct
FROM base
GROUP BY day1_icu, los_cat
ORDER BY 
  CASE WHEN day1_icu = 'ICU' THEN 1 ELSE 2 END,
  CASE 
    WHEN los_cat = '1-3' THEN 1 
    WHEN los_cat = '4-7' THEN 2 
    ELSE 3 
  END;