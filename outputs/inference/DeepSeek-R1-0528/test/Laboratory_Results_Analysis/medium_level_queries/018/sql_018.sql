WITH filtered_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    -- Age filter (90-100)
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 90 AND 100
    -- ACS diagnosis filter
    AND a.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        -- ICD-9: 410.x or 4111
        (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code = '4111')) OR 
        -- ICD-10: I21.x, I22.x, or I200
        (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code = 'I200'))
    )
),
first_troponin AS (
  SELECT 
    hadm_id, 
    valuenum AS troponin_value
  FROM (
    SELECT 
      hadm_id, 
      charttime, 
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 51003  -- Troponin T
      AND valuenum IS NOT NULL  -- Ensure numeric value
  ) 
  WHERE rn = 1  -- First Troponin T per admission
),
categorized_troponin AS (
  SELECT 
    f.hadm_id,
    f.admittime,
    f.dischtime,
    t.troponin_value,
    CASE 
      WHEN t.troponin_value <= 0.01 THEN 'normal'
      WHEN t.troponin_value > 0.01 AND t.troponin_value <= 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS troponin_category
  FROM filtered_admissions f
  INNER JOIN first_troponin t
    ON f.hadm_id = t.hadm_id  -- Exclude admissions without Troponin T
)
SELECT 
  troponin_category,
  COUNT(*) AS count_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days
FROM categorized_troponin
GROUP BY troponin_category
ORDER BY troponin_category;