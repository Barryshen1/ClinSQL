WITH acs_icd_codes AS (
  -- List of ACS ICD codes (ICD-9 and ICD-10)
  SELECT '410' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '4100', 9 UNION ALL
  SELECT '4101', 9 UNION ALL
  SELECT '4102', 9 UNION ALL
  SELECT '4103', 9 UNION ALL
  SELECT '4104', 9 UNION ALL
  SELECT '4105', 9 UNION ALL
  SELECT '4106', 9 UNION ALL
  SELECT '4107', 9 UNION ALL
  SELECT '4108', 9 UNION ALL
  SELECT '4109', 9 UNION ALL
  SELECT '4111', 9 UNION ALL
  SELECT 'I210', 10 UNION ALL
  SELECT 'I211', 10 UNION ALL
  SELECT 'I212', 10 UNION ALL
  SELECT 'I213', 10 UNION ALL
  SELECT 'I214', 10 UNION ALL
  SELECT 'I219', 10 UNION ALL
  SELECT 'I220', 10 UNION ALL
  SELECT 'I221', 10 UNION ALL
  SELECT 'I222', 10 UNION ALL
  SELECT 'I228', 10 UNION ALL
  SELECT 'I229', 10 UNION ALL
  SELECT 'I200', 10
),
acs_admissions AS (
  -- Admissions with ACS diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN acs_icd_codes c
    ON d.icd_code = c.icd_code AND d.icd_version = c.icd_version
),
male_35_45_acs AS (
  -- Male ACS admissions aged 35-45
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         p.anchor_age, p.gender
  FROM acs_admissions acs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON acs.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
admission_los AS (
  -- Calculate LOS and assign LOS group
  SELECT subject_id, hadm_id, anchor_age, gender,
         admittime, dischtime,
         DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
         CASE
           WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
           WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
           ELSE NULL
         END AS los_group
  FROM male_35_45_acs
),
ultrasound_procedures AS (
  -- Procedures with ultrasound/echo/echocardiogram in long_title
  SELECT DISTINCT p.subject_id, p.hadm_id, p.icd_code, p.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ultrasound%'
     OR LOWER(d.long_title) LIKE '%echo%'
     OR LOWER(d.long_title) LIKE '%echocardiogram%'
),
ultrasound_counts AS (
  -- Count ultrasound procedures per admission
  SELECT a.subject_id, a.hadm_id, COUNT(u.icd_code) AS ultrasound_count
  FROM admission_los a
  LEFT JOIN ultrasound_procedures u
    ON a.subject_id = u.subject_id AND a.hadm_id = u.hadm_id
  GROUP BY a.subject_id, a.hadm_id
),
final AS (
  -- Combine LOS group and ultrasound counts
  SELECT a.hadm_id, a.los_group, c.ultrasound_count
  FROM admission_los a
  LEFT JOIN ultrasound_counts c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  WHERE a.los_group IS NOT NULL
)
SELECT
  los_group,
  COUNT(DISTINCT hadm_id) AS patient_count,
  ROUND(AVG(IFNULL(ultrasound_count, 0)), 2) AS mean_ultrasound_per_admission
FROM final
GROUP BY los_group
ORDER BY los_group;