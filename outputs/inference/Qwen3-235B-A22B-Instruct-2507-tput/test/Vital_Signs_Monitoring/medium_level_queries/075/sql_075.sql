WITH map_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%arterial pressure%mean%'
     OR LOWER(label) LIKE '%map%'
),
patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 56 AND 66
),
stay_map AS (
  SELECT
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    AVG(ce.valuenum) AS mean_map
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN map_item mi ON 1=1
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON i.stay_id = ce.stay_id
    AND mi.itemid = ce.itemid
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.outtime
  WHERE ce.valuenum IS NOT NULL
  GROUP BY i.subject_id, i.stay_id, i.hadm_id
),
stroke_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%stroke%'
),
stroke_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN stroke_codes sc
    ON di.icd_code = sc.icd_code
    AND di.icd_version = sc.icd_version
),
stay_with_outcome AS (
  SELECT
    pa.subject_id,
    sm.stay_id,
    sm.hadm_id,
    sm.mean_map,
    CASE WHEN sd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_stroke
  FROM patient_ages pa
  INNER JOIN stay_map sm ON pa.subject_id = sm.subject_id
  LEFT JOIN stroke_diagnoses sd ON sm.hadm_id = sd.hadm_id
),
categorized AS (
  SELECT
    stay_id,
    had_stroke,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map >= 65 AND mean_map < 75 THEN '65-74'
      WHEN mean_map >= 75 AND mean_map < 85 THEN '75-84'
      WHEN mean_map >= 85 THEN '>=85'
      ELSE NULL
    END AS map_category
  FROM stay_with_outcome
  WHERE mean_map IS NOT NULL
)
SELECT
  map_category,
  COUNT(*) AS patient_count,
  AVG(CAST(had_stroke AS FLOAT64)) AS stroke_rate
FROM categorized
WHERE map_category IS NOT NULL
GROUP BY map_category
ORDER BY map_category;