WITH acs_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id,
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE (
      -- ICD-9 ACS
      (di.icd_version = 9 AND di.icd_code LIKE '410%' )
      OR (di.icd_version = 9 AND di.icd_code LIKE '411%')
      OR (di.icd_version = 9 AND di.icd_code LIKE '412%')
      OR (di.icd_version = 9 AND di.icd_code LIKE '413%')
      -- ICD-10 ACS
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I20%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I22%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I24%')
    )
),
admissions_filtered AS (
  SELECT a.subject_id, a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),
ultrasound_counts AS (
  SELECT pr.subject_id, pr.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY pr.subject_id, pr.hadm_id
)
SELECT 
  CASE 
    WHEN af.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN af.los_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_group,
  ap.diagnosis_type,
  AVG(COALESCE(uc.ultrasound_count, 0)) AS mean_ultrasounds,
  MIN(COALESCE(uc.ultrasound_count, 0)) AS min_ultrasounds,
  MAX(COALESCE(uc.ultrasound_count, 0)) AS max_ultrasounds
FROM admissions_filtered af
JOIN acs_patients ap
  ON af.subject_id = ap.subject_id AND af.hadm_id = ap.hadm_id
LEFT JOIN ultrasound_counts uc
  ON af.subject_id = uc.subject_id AND af.hadm_id = uc.hadm_id
WHERE af.los_days BETWEEN 1 AND 7
GROUP BY los_group, ap.diagnosis_type
ORDER BY los_group, ap.diagnosis_type;