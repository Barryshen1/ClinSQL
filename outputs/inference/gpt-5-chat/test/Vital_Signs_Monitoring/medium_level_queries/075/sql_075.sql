WITH map_itemids AS (
  -- Identify all itemids for mean arterial pressure in ICU charted data
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
    OR LOWER(label) LIKE '%arterial bp mean%'
),
map_per_stay AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM map_itemids)
    AND ce.valuenum IS NOT NULL
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),
stroke_flags AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id,
    1 AS stroke_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE (
    -- Common ischemic stroke ICD-9/ICD-10
    (di.icd_version = 9 AND di.icd_code LIKE '434%')
    OR (di.icd_version = 10 AND (di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'I64%'))
  )
),
cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    mps.hadm_id,
    mps.stay_id,
    mps.mean_map,
    CASE
      WHEN mps.mean_map < 65 THEN '<65'
      WHEN mps.mean_map BETWEEN 65 AND 74 THEN '65-74'
      WHEN mps.mean_map BETWEEN 75 AND 84 THEN '75-84'
      ELSE '>=85'
    END AS map_category,
    IF(sf.stroke_flag IS NOT NULL, 1, 0) AS stroke_flag
  FROM map_per_stay mps
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON mps.subject_id = p.subject_id
  LEFT JOIN stroke_flags sf
    ON mps.subject_id = sf.subject_id
    AND mps.hadm_id = sf.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
)
SELECT
  map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(100 * SUM(stroke_flag) / COUNT(DISTINCT subject_id), 2) AS stroke_rate_percent
FROM cohort
GROUP BY map_category
ORDER BY
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    ELSE 4
  END;