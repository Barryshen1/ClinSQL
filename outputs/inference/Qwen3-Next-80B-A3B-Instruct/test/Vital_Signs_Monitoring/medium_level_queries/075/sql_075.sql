WITH map_per_stay AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    AVG(ce.valuenum) AS mean_map
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p 
    ON i.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents ce 
    ON i.stay_id = ce.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di 
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND di.label = 'Mean Arterial Pressure'
    AND ce.valuenum IS NOT NULL
  GROUP BY 
    i.stay_id, i.hadm_id
),
stroke_flag AS (
  SELECT DISTINCT
    i.stay_id,
    CASE 
      WHEN di.icd_code LIKE 'I6%' THEN 1 
      ELSE 0 
    END AS has_stroke
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  LEFT JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di 
    ON i.hadm_id = di.hadm_id
  LEFT JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddi 
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE 
    di.icd_code LIKE 'I6%' 
    OR di.icd_code IS NULL
),
mapped_stays AS (
  SELECT 
    m.stay_id,
    m.mean_map,
    sf.has_stroke,
    CASE 
      WHEN m.mean_map < 65 THEN '<65'
      WHEN m.mean_map BETWEEN 65 AND 74 THEN '65-74'
      WHEN m.mean_map BETWEEN 75 AND 84 THEN '75-84'
      WHEN m.mean_map >= 85 THEN '>=85'
    END AS map_category
  FROM 
    map_per_stay m
  LEFT JOIN 
    stroke_flag sf 
    ON m.stay_id = sf.stay_id
)
SELECT 
  map_category,
  COUNT(*) AS patient_count,
  SUM(has_stroke) * 1.0 / COUNT(*) AS stroke_rate
FROM 
  mapped_stays
WHERE 
  map_category IS NOT NULL
GROUP BY 
  map_category
ORDER BY 
  map_category;