WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
diagnosis_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '7865%') OR  -- Chest Pain (ICD-9)
    (icd_version = 10 AND icd_code LIKE 'R07%') OR   -- Chest Pain (ICD-10)
    (icd_version = 9 AND icd_code LIKE '410%') OR    -- AMI (ICD-9)
    (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))  -- AMI (ICD-10)
),
filtered_cohort AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime
  FROM cohort c
  INNER JOIN diagnosis_adm d
    ON c.hadm_id = d.hadm_id
  WHERE c.age_at_admit BETWEEN 81 AND 91
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_value,
    c.admittime,
    c.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN filtered_cohort c
    ON l.hadm_id = c.hadm_id
  WHERE 
    l.itemid = 51003  -- Troponin T (High Sens)
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/L'  -- Ensure consistent units
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
),
classified_troponin AS (
  SELECT 
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN troponin_value < 14 THEN 'normal'
      WHEN troponin_value <= 52 THEN 'borderline'  -- 14-52 inclusive
      ELSE 'myocardial injury'                     -- >52
    END AS category
  FROM first_troponin
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los
FROM classified_troponin
GROUP BY category
ORDER BY category;