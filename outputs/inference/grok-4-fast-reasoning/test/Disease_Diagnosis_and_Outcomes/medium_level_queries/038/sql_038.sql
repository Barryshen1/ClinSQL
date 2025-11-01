WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` ic 
           WHERE ic.hadm_id = a.hadm_id) AS in_icu,
    EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
           WHERE d.hadm_id = a.hadm_id 
           AND ((d.icd_version = 9 AND (d.icd_code LIKE '585%' OR d.icd_code = '586')) 
                OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%'))) AS has_ckd,
    EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
           WHERE d.hadm_id = a.hadm_id 
           AND ((d.icd_version = 9 AND d.icd_code LIKE '250%') 
                OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' 
                                            OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' 
                                            OR d.icd_code LIKE 'E14%')))) AS has_dm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 80 AND 90
    AND EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
               WHERE d.hadm_id = a.hadm_id 
               AND ((d.icd_version = 9 AND d.icd_code LIKE '428%') 
                    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')))
)
SELECT 
  CASE WHEN in_icu THEN 'ICU' ELSE 'Non-ICU' END AS location,
  CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS mortality_pct,
  SUM(CASE WHEN has_ckd THEN 1 ELSE 0 END) AS n_ckd,
  ROUND(AVG(CASE WHEN has_ckd THEN 1.0 ELSE 0.0 END) * 100, 2) AS ckd_pct,
  SUM(CASE WHEN has_dm THEN 1 ELSE 0 END) AS n_dm,
  ROUND(AVG(CASE WHEN has_dm THEN 1.0 ELSE 0.0 END) * 100, 2) AS dm_pct
FROM cohort
GROUP BY location, los_group
ORDER BY 
  CASE WHEN location = 'ICU' THEN 1 ELSE 0 END,
  CASE WHEN los_group = '<8 days' THEN 1 ELSE 0 END;