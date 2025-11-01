SELECT
  CASE 
    WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
    WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
    ELSE '≥8' 
  END AS los_category,
  CASE 
    WHEN a.admission_type = 'EMERGENCY' THEN 'emergent' 
    ELSE 'non-emergent' 
  END AS admission_category,
  ROUND(100.0 * SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
  APPROX_QUANTILES(CASE WHEN a.hospital_expire_flag = 1 THEN DATE_DIFF(a.deathtime, a.admittime, DAY) END, 2)[OFFSET(1)] AS median_time_to_death
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 66 AND 76
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE a.subject_id = d.subject_id 
      AND a.hadm_id = d.hadm_id
      AND d.icd_code LIKE 'I21%' 
      AND d.icd_version = 10
  )
GROUP BY los_category, admission_category;