WITH acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, 
    a.admittime, a.dischtime,
    p.gender, p.anchor_age,
    DATE_DIFF(DATETIME(a.dischtime), DATETIME(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND (
      -- ICD-9 ACS patterns
      (d.icd_version = 9 AND (
        d.icd_code LIKE '410%' OR
        d.icd_code = '4111' OR
        d.icd_code = '41181' OR
        d.icd_code = '41189'
      ))
      OR
      -- ICD-10 ACS patterns
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'I20.0%' OR
        d.icd_code LIKE 'I21%' OR
        d.icd_code LIKE 'I22%'
      ))
      OR
      -- Fallback text search in descriptions
      LOWER(dd.long_title) LIKE '%acute myocardial infarction%' OR
      LOWER(dd.long_title) LIKE '%unstable angina%'
    )
)
, ultrasound_counts AS (
  SELECT aa.subject_id, aa.hadm_id,
    COUNT(proc.icd_code) AS num_ultrasounds
  FROM acs_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON aa.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
  WHERE dp.long_title IS NULL 
        OR LOWER(dp.long_title) LIKE '%ultrasound%'
        OR LOWER(dp.long_title) LIKE '%echocardiogram%'
        OR LOWER(dp.long_title) LIKE '%echocardiography%'
  GROUP BY aa.subject_id, aa.hadm_id
)
SELECT
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN 'LOS 1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN 'LOS 4-7 days'
  END AS los_group,
  COUNT(DISTINCT aa.subject_id) AS patient_count,
  AVG(COALESCE(uc.num_ultrasounds, 0)) AS mean_ultrasounds_per_admission
FROM acs_admissions aa
LEFT JOIN ultrasound_counts uc
  ON aa.subject_id = uc.subject_id
  AND aa.hadm_id = uc.hadm_id
WHERE los_days BETWEEN 1 AND 7
GROUP BY los_group
ORDER BY los_group;