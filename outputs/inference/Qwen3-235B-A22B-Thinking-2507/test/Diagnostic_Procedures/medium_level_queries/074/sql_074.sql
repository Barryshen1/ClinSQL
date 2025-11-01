WITH stroke_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '434%')
        )
    )
),
admission_duration AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) + 1 AS stay_days
  FROM stroke_admissions
  WHERE dischtime IS NOT NULL
    AND DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) + 1 BETWEEN 1 AND 7
),
icu_status AS (
  SELECT 
    a.hadm_id,
    a.stay_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu
  FROM admission_duration a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
),
imaging_procedures AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE 
    (p.icd_version = 10 AND p.icd_code LIKE 'B%')
    OR (p.icd_version = 9 AND (p.icd_code LIKE '87%' OR p.icd_code LIKE '88%'))
  GROUP BY p.hadm_id
)
SELECT
  has_icu AS icu_status,
  CASE 
    WHEN stay_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN stay_days BETWEEN 5 AND 7 THEN '5-7'
  END AS stay_group,
  AVG(COALESCE(imaging_count, 0)) AS mean_procedures,
  MIN(COALESCE(imaging_count, 0)) AS min_procedures,
  MAX(COALESCE(imaging_count, 0)) AS max_procedures
FROM icu_status
LEFT JOIN imaging_procedures
  USING (hadm_id)
GROUP BY has_icu, stay_group
ORDER BY has_icu, stay_group;