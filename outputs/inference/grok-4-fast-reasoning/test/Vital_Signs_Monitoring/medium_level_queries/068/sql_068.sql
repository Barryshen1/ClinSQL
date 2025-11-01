WITH cohort AS (
  SELECT DISTINCT 
    p.subject_id, 
    i.hadm_id, 
    i.stay_id,
    p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year BETWEEN 41 AND 51
),
map_measurements AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id, 
    ce.valuenum AS map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c 
    ON ce.subject_id = c.subject_id 
    AND ce.hadm_id = c.hadm_id 
    AND ce.stay_id = c.stay_id
  WHERE ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 1 AND 300
),
hadm_map_cats AS (
  SELECT DISTINCT 
    m.subject_id,
    m.hadm_id,
    CASE 
      WHEN m.map < 65 THEN '<65'
      WHEN m.map < 75 THEN '65-74'
      WHEN m.map < 85 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM map_measurements m
),
has_stroke AS (
  SELECT DISTINCT 
    di.subject_id, 
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN cohort c 
    ON di.subject_id = c.subject_id 
    AND di.hadm_id = c.hadm_id
  WHERE 
    (di.icd_version = 9 
     AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%' 
          OR di.icd_code LIKE '433%' OR di.icd_code LIKE '434%' OR di.icd_code LIKE '436'))
    OR (di.icd_version = 10 
        AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' 
             OR di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'I64%'))
)
SELECT 
  map_category,
  COUNT(DISTINCT hmc.subject_id) AS patient_count,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN hs.hadm_id IS NOT NULL THEN hmc.subject_id END) / COUNT(DISTINCT hmc.subject_id), 2) AS stroke_rate_percent
FROM hadm_map_cats hmc
LEFT JOIN has_stroke hs 
  ON hmc.subject_id = hs.subject_id 
  AND hmc.hadm_id = hs.hadm_id
GROUP BY map_category
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;