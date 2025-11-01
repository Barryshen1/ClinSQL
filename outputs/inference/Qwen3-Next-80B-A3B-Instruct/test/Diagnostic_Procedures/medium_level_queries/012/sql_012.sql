WITH acs_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND did.icd_code IN ('I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I20.0')
    AND di.icd_version = 10
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
ultrasound_procedures AS (
  SELECT
    ie.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM physionet-data.mimiciv_3_1_icu.procedureevents ie
  JOIN physionet-data.mimiciv_3_1_icu.icustays icu ON ie.stay_id = icu.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items di ON ie.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%echocardi%' 
     OR LOWER(di.label) LIKE '%ultrasound%'
     OR LOWER(di.label) LIKE '%echo%'
  GROUP BY ie.hadm_id
),
los_groups AS (
  SELECT
    aa.hadm_id,
    aa.los_days,
    CASE 
      WHEN aa.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN aa.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM acs_admissions aa
  WHERE aa.los_days BETWEEN 1 AND 7
)
SELECT
  lg.los_group,
  COUNT(lg.hadm_id) AS patient_count,
  AVG(COALESCE(up.ultrasound_count, 0)) AS mean_ultrasounds_per_admission
FROM los_groups lg
LEFT JOIN ultrasound_procedures up ON lg.hadm_id = up.hadm_id
GROUP BY lg.los_group
ORDER BY lg.los_group;