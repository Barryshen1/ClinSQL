WITH base_data AS (
  SELECT
    a.hadm_id,
    CASE WHEN MAX(i.stay_id) IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital,
    a.hospital_expire_flag,
    COUNT(CASE WHEN d.seq_num > 1 THEN 1 END) AS comorbidity_count,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'E1%') 
      THEN 1 ELSE 0 
    END) AS diabetes_flag,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%') 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%') 
      THEN 1 ELSE 0 
    END) AS ckd_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
  GROUP BY a.hadm_id, a.dischtime, a.admittime, a.hospital_expire_flag
)
SELECT
  icu_status,
  CASE WHEN los_hospital < 8 THEN '<8' ELSE '>=8' END AS los_group,
  CASE
    WHEN comorbidity_count <= 1 THEN '0-1'
    WHEN comorbidity_count = 2 THEN '2'
    ELSE '>=3'
  END AS comorbidity_group,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
  MEDIAN(los_hospital) AS median_los,
  ROUND(SUM(ckd_flag) * 100.0 / COUNT(*), 2) AS ckd_prevalence,
  ROUND(SUM(diabetes_flag) * 100.0 / COUNT(*), 2) AS diabetes_prevalence
FROM base_data
GROUP BY icu_status, los_group, comorbidity_group
ORDER BY icu_status, los_group, comorbidity_group;