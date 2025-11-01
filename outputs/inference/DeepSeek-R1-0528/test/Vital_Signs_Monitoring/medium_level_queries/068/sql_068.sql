WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year, 
    icu.hadm_id, 
    icu.stay_id,
    icu.intime,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_icu_admission BETWEEN 41 AND 51
),
map_events AS (
  SELECT 
    ce.subject_id, 
    ce.stay_id, 
    ce.valuenum AS map_value,
    CASE 
      WHEN ce.valuenum < 65 THEN '<65'
      WHEN ce.valuenum BETWEEN 65 AND 74 THEN '65-74'
      WHEN ce.valuenum BETWEEN 75 AND 84 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_cohort fc
    ON ce.stay_id = fc.stay_id
  WHERE 
    ce.itemid IN (220052, 220181)  -- MAP item IDs
    AND ce.valuenum IS NOT NULL    -- Only numeric values
),
stroke_patients AS (
  SELECT DISTINCT 
    diag.subject_id, 
    diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN filtered_cohort fc
    ON diag.hadm_id = fc.hadm_id
  WHERE 
    (diag.icd_version = 9 AND diag.icd_code BETWEEN '430' AND '438') OR  -- ICD-9 stroke codes
    (diag.icd_version = 10 AND diag.icd_code LIKE 'I6%')                 -- ICD-10 stroke codes
),
per_category AS (
  SELECT 
    me.map_category,
    fc.subject_id,
    fc.hadm_id
  FROM map_events me
  INNER JOIN filtered_cohort fc
    ON me.subject_id = fc.subject_id AND me.stay_id = fc.stay_id
  GROUP BY me.map_category, fc.subject_id, fc.hadm_id  -- Unique admissions per category
)
SELECT 
  map_category,
  COUNT(*) AS patient_admission_count,
  COUNTIF(sp.subject_id IS NOT NULL) AS stroke_patient_admission_count,
  ROUND(COUNTIF(sp.subject_id IS NOT NULL) / COUNT(*), 4) AS stroke_rate
FROM per_category pc
LEFT JOIN stroke_patients sp 
  ON pc.subject_id = sp.subject_id AND pc.hadm_id = sp.hadm_id
GROUP BY map_category
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;