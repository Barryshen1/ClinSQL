WITH map_data AS (
  -- Extract MAP measurements per stay, filtered to stay duration
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id 
    AND c.stay_id = i.stay_id
  WHERE 
    c.itemid IN (220052, 52)  -- MAP itemids
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
    AND c.charttime BETWEEN i.intime AND i.outtime
),
stay_map AS (
  -- Compute per-stay mean MAP
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    AVG(valuenum) AS mean_map
  FROM map_data
  GROUP BY subject_id, hadm_id, stay_id
  HAVING mean_map IS NOT NULL  -- Exclude stays with no valid MAP
),
patient_stays AS (
  -- Base stays with demographics and stroke flag
  SELECT 
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    p.gender,
    p.anchor_age,
    CASE 
      WHEN d.subject_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS stroke_flag
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON s.subject_id = p.subject_id
  LEFT JOIN (
    -- Stays with any stroke ICD-10 code
    SELECT DISTINCT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_version = '10'
      AND UPPER(icd_code) LIKE 'I6%'
  ) d
  ON s.subject_id = d.subject_id AND s.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
),
categorized_stays AS (
  -- Join MAP and add categories
  SELECT 
    ps.*,
    sm.mean_map,
    CASE 
      WHEN sm.mean_map < 65 THEN '<65'
      WHEN sm.mean_map >= 65 AND sm.mean_map <= 74 THEN '65-74'
      WHEN sm.mean_map >= 75 AND sm.mean_map <= 84 THEN '75-84'
      WHEN sm.mean_map >= 85 THEN '>=85'
    END AS map_category
  FROM patient_stays ps
  LEFT JOIN stay_map sm
  ON ps.subject_id = sm.subject_id 
    AND ps.hadm_id = sm.hadm_id 
    AND ps.stay_id = sm.stay_id
  WHERE sm.mean_map IS NOT NULL  -- Only stays with MAP data
)
-- Aggregate by category
SELECT 
  map_category,
  COUNT(stay_id) AS patient_counts,  -- Actually stay counts, per "per-stay"
  SUM(stroke_flag) AS stroke_counts,
  ROUND(SUM(stroke_flag) * 1.0 / COUNT(stay_id), 4) AS stroke_rate
FROM categorized_stays
GROUP BY map_category
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;