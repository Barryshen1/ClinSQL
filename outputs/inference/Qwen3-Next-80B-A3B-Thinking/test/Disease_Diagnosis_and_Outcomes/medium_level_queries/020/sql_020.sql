WITH sepsis_patients AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (d.icd_version = 9 AND (d.icd_code LIKE '038%' OR d.icd_code = '995.91'))
     OR (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%'))
  AND NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    WHERE d2.subject_id = d.subject_id
      AND d2.hadm_id = d.hadm_id
      AND ((d2.icd_version = 9 AND d2.icd_code = '995.92')
           OR (d2.icd_version = 10 AND d2.icd_code = 'R65.21'))
  )
),
main_data AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
        AND i.intime <= a.admittime + INTERVAL 24 HOUR
    ) THEN 'Yes' ELSE 'No' END AS icu_day1_status,
    CASE WHEN a.hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) ELSE NULL END AS days_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN sepsis_patients s ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
)
SELECT
  CASE
    WHEN los_days <= 3 THEN '≤3'
    WHEN los_days BETWEEN 4 AND 6 THEN '4-6'
    WHEN los_days BETWEEN 7 AND 10 THEN '7-10'
    ELSE '>10'
  END AS los_category,
  icu_day1_status,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percentage,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_death) AS median_days_to_death
FROM main_data
GROUP BY los_category, icu_day1_status;