WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_year - EXTRACT(YEAR FROM a.admittime) + p.anchor_age) BETWEEN 53 AND 63
),
diabetes_hf AS (
  SELECT 
    e.hadm_id,
    e.admittime,
    e.dischtime,
    e.subject_id
  FROM eligible_admissions e
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE di.hadm_id = e.hadm_id
      AND LOWER(d.long_title) LIKE '%diabetes%'
      AND d.icd_code LIKE 'E11%' -- Type 2 diabetes
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE di.hadm_id = e.hadm_id
      AND LOWER(d.long_title) LIKE '%heart failure%'
      AND d.icd_code LIKE 'I50%'
  )
),
glp1_prescriptions AS (
  SELECT 
    hadm_id,
    starttime,
    drug,
    route
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE LOWER(drug) IN ('exenatide', 'liraglutide', 'semaglutide', 'dulaglutide')
    OR LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
),
timing_flags AS (
  SELECT 
    dh.hadm_id,
    MAX(CASE 
      WHEN p.starttime IS NOT NULL 
       AND p.starttime >= dh.admittime 
       AND p.starttime <= TIMESTAMP_ADD(dh.admittime, INTERVAL 24 HOUR)
      THEN 1 ELSE 0 END) AS initiated_early,
    MAX(CASE 
      WHEN p.starttime IS NOT NULL 
       AND p.starttime >= TIMESTAMP_ADD(dh.dischtime, INTERVAL -12 HOUR)
       AND p.starttime <= dh.dischtime
      THEN 1 ELSE 0 END) AS initiated_late
  FROM diabetes_hf dh
  LEFT JOIN glp1_prescriptions p
    ON dh.hadm_id = p.hadm_id
  GROUP BY dh.hadm_id
)
SELECT
  ROUND(100.0 * SUM(initiated_early) / COUNT(*), 2) AS pct_initiated_early,
  ROUND(100.0 * SUM(initiated_late) / COUNT(*), 2) AS pct_initiated_late,
  COUNT(*) AS total_admissions
FROM timing_flags;