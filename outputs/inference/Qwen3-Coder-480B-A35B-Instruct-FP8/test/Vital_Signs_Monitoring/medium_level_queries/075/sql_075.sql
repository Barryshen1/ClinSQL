WITH cohort AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    AVG(ce.valuenum) AS mean_map
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND di.label = 'MAP'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.outtime
  GROUP BY 
    p.subject_id, i.stay_id, i.hadm_id, i.intime, i.outtime
),

map_categories AS (
  SELECT 
    *,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map >= 65 AND mean_map <= 74 THEN '65–74'
      WHEN mean_map >= 75 AND mean_map <= 84 THEN '75–84'
      ELSE '≥85'
    END AS map_category
  FROM cohort
),

stroke_flag AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN (
        (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^43[0-8]'))
        OR
        (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I6[0-9]'))
      ) THEN 1 ELSE 0 END) AS is_stroke
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY 
    hadm_id
)

SELECT 
  mc.map_category,
  COUNT(DISTINCT mc.subject_id) AS patient_count,
  SUM(sf.is_stroke) AS stroke_count
FROM 
  map_categories mc
LEFT JOIN 
  stroke_flag sf
  ON mc.hadm_id = sf.hadm_id
GROUP BY 
  mc.map_category
ORDER BY 
  CASE mc.map_category
    WHEN '<65' THEN 1
    WHEN '65–74' THEN 2
    WHEN '75–84' THEN 3
    WHEN '≥85' THEN 4
  END;