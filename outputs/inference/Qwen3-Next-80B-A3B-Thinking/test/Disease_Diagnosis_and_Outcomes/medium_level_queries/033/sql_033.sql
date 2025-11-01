WITH target_patients AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS in_icu,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '996%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'T81%')
        )
    )
),
comorbidity_counts AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT
  CASE WHEN in_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
  CASE WHEN los_days <= 5 THEN 'LOS <=5' ELSE 'LOS >5' END AS los_group,
  CASE
    WHEN comorbidity_count <= 1 THEN '0-1'
    WHEN comorbidity_count = 2 THEN '2'
    ELSE '>=3'
  END AS comorbidity_bin,
  COUNT(*) AS N,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  AVG(comorbidity_count) AS avg_comorbidity_count
FROM target_patients
JOIN comorbidity_counts 
  ON target_patients.hadm_id = comorbidity_counts.hadm_id
GROUP BY icu_status, los_group, comorbidity_bin;