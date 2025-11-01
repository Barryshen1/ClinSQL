WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
acs_admissions AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM cohort c
  WHERE 
    -- Age filter (46-56)
    c.age_admit BETWEEN 46 AND 56
    -- ACS diagnosis check
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        c.hadm_id = diag.hadm_id
        AND (
          -- ICD-9 codes
          (diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code IN ('411.1', '411.81')))
          OR
          -- ICD-10 codes
          (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code = 'I20.0'))
        )
    )
),
first_troponin AS (
  SELECT
    a.hadm_id,
    le.valuenum AS troponin_value,
    -- Get first non-null hs-TnT result per admission
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY le.charttime) AS rn
  FROM acs_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  WHERE 
    le.itemid = 51006  -- hs-TnT itemid
    AND le.valuenum IS NOT NULL
),
categorized_troponin AS (
  SELECT
    hadm_id,
    troponin_value,
    CASE
      WHEN troponin_value <= 14 THEN 'Normal'
      WHEN troponin_value BETWEEN 15 AND 19 THEN 'Borderline'
      WHEN troponin_value >= 20 THEN 'Myocardial Injury'
    END AS troponin_category
  FROM first_troponin
  WHERE rn = 1  -- First result only
),
combined_data AS (
  SELECT
    ct.hadm_id,
    ct.troponin_category,
    -- Calculate length of stay in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM categorized_troponin ct
  INNER JOIN acs_admissions a
    ON ct.hadm_id = a.hadm_id
)
-- Final aggregation
SELECT
  troponin_category,
  COUNT(*) AS count_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM combined_data
GROUP BY troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;