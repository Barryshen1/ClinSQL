WITH sbp_data AS (
  -- Identify SBP itemids
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' 
    AND (LOWER(label) LIKE '%blood pressure%' OR LOWER(label) LIKE '%sbp%')
),
first_24h_sbp AS (
  -- SBP readings in first 24h per stay
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.valuenum AS sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN sbp_data si ON ce.itemid = si.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.subject_id = icu.subject_id 
    AND ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ce.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND icu.los >= 1
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0
),
stay_averages AS (
  -- Average SBP per stay
  SELECT 
    subject_id,
    stay_id,
    AVG(sbp) AS avg_sbp_per_stay
  FROM first_24h_sbp
  GROUP BY subject_id, stay_id
  HAVING avg_sbp_per_stay IS NOT NULL  -- Exclude stays with no readings
),
patient_averages AS (
  -- Average across stays per patient
  SELECT 
    subject_id,
    AVG(avg_sbp_per_stay) AS avg_sbp
  FROM stay_averages
  GROUP BY subject_id
  HAVING COUNT(stay_id) >= 1  -- At least one qualifying stay
)
-- Bin and count unique patients
SELECT 
  CASE 
    WHEN avg_sbp < 140 THEN '<140 mmHg'
    WHEN avg_sbp >= 140 AND avg_sbp < 160 THEN '140–159 mmHg'
    ELSE '>=160 mmHg'
  END AS sbp_bin,
  COUNT(DISTINCT subject_id) AS patient_count
FROM patient_averages
GROUP BY sbp_bin
ORDER BY 
  CASE sbp_bin
    WHEN '<140 mmHg' THEN 1
    WHEN '140–159 mmHg' THEN 2
    ELSE 3
  END;