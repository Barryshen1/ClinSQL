WITH cohort AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_icu BETWEEN 56 AND 66
),
map_data AS (
  SELECT 
    fc.stay_id,
    fc.subject_id,
    fc.hadm_id,
    AVG(ce.valuenum) AS avg_map
  FROM filtered_cohort fc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fc.stay_id = ce.stay_id
  WHERE ce.itemid IN (220052, 220181)  -- MAP item IDs
    AND ce.valuenum BETWEEN 0 AND 300  -- Valid MAP range
  GROUP BY fc.stay_id, fc.subject_id, fc.hadm_id
),
stroke_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    -- ICD-9 Stroke Codes
    (icd_version = 9 AND 
      REGEXP_CONTAINS(icd_code, r'^(430|431|432|433|434|436)')) OR 
    -- ICD-10 Stroke Codes
    (icd_version = 10 AND 
      REGEXP_CONTAINS(icd_code, r'^(I6[0-4])'))
),
combined_data AS (
  SELECT 
    md.stay_id,
    md.subject_id,
    md.hadm_id,
    md.avg_map,
    CASE WHEN sa.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS stroke_flag
  FROM map_data md
  LEFT JOIN stroke_admissions sa
    ON md.hadm_id = sa.hadm_id
),
categorized AS (
  SELECT 
    *,
    CASE 
      WHEN avg_map < 65 THEN '<65'
      WHEN avg_map < 75 THEN '65-74'
      WHEN avg_map < 85 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM combined_data
)
SELECT 
  map_category,
  COUNT(*) AS count_stays,
  COUNT(DISTINCT subject_id) AS count_patients,
  SUM(stroke_flag) AS count_strokes,
  ROUND(SAFE_DIVIDE(SUM(stroke_flag), COUNT(*)), 4) AS stroke_rate
FROM categorized
GROUP BY map_category
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;