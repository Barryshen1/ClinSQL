WITH heart_failure_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(dicd.long_title) LIKE '%heart failure%'
),
ckd_diabetes_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN LOWER(dicd.long_title) LIKE '%chronic kidney%' 
              OR LOWER(dicd.long_title) LIKE '%ckd%' 
              OR d.icd_code LIKE '585%' 
              OR d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(dicd.long_title) LIKE '%diabetes%' 
              OR d.icd_code LIKE '250%' 
              OR d.icd_code LIKE 'E10%' 
              OR d.icd_code LIKE 'E11%' 
              OR d.icd_code LIKE 'E12%' 
              OR d.icd_code LIKE 'E13%' 
              OR d.icd_code LIKE 'E14%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  GROUP BY hadm_id
)
SELECT
  hfp.is_icu,
  CASE WHEN hfp.los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_stratum,
  ROUND(AVG(hfp.hospital_expire_flag * 100.0), 2) AS in_hospital_mortality_pct,
  ROUND(AVG(ckd.has_ckd * 100.0), 2) AS ckd_prevalence_pct,
  ROUND(AVG(ckd.has_diabetes * 100.0), 2) AS diabetes_prevalence_pct
FROM heart_failure_patients hfp
LEFT JOIN ckd_diabetes_flags ckd
  ON hfp.hadm_id = ckd.hadm_id
GROUP BY hfp.is_icu, los_stratum
ORDER BY hfp.is_icu, los_stratum;