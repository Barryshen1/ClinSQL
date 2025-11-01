WITH icu_stays_filtered AS (
  SELECT 
    s.stay_id,
    s.hadm_id,
    s.intime,
    -- Compute age at ICU admission using standard MIMIC-IV approximation
    EXTRACT(YEAR FROM s.intime) - (p.anchor_year - p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM s.intime) - (p.anchor_year - p.anchor_age) BETWEEN 56 AND 66
),
map_per_stay AS (
  SELECT 
    s.stay_id,
    AVG(c.valuenum) AS mean_map
  FROM icu_stays_filtered s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  WHERE c.itemid IN (220052, 225312)  -- Valid MAP item IDs
    AND c.valuenum IS NOT NULL
  GROUP BY s.stay_id
),
stroke_per_admission AS (
  SELECT 
    d.hadm_id,
    COALESCE(MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code IN ('430','431','432','433','434','436')) 
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' 
          OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%'))
      THEN 1 ELSE 0 END), 0) AS has_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
)

SELECT
  CASE 
    WHEN m.mean_map < 65 THEN '<65'
    WHEN m.mean_map BETWEEN 65 AND 74 THEN '65-74'
    WHEN m.mean_map BETWEEN 75 AND 84 THEN '75-84'
    WHEN m.mean_map >= 85 THEN '>=85'
  END AS map_category,
  COUNT(*) AS patient_count,
  AVG(s.has_stroke) AS stroke_rate
FROM map_per_stay m
INNER JOIN icu_stays_filtered f ON m.stay_id = f.stay_id
INNER JOIN stroke_per_admission s ON f.hadm_id = s.hadm_id
GROUP BY map_category
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;