WITH MAP_MEAS AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    CASE
      WHEN ce.valuenum < 65 THEN '<65'
      WHEN ce.valuenum < 75 THEN '65-74'
      WHEN ce.valuenum < 85 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` cs
    ON cs.subject_id = ce.subject_id
   AND cs.hadm_id = ce.hadm_id
   AND cs.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ce.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = ce.subject_id
  WHERE ce.charttime >= cs.intime
    AND ce.charttime <= cs.outtime
    AND ce.valuenum IS NOT NULL
    AND (LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%')
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
),
-- Part 2: stroke definitions based on ICD codes (stroke in any ICD version)
STROKE_PAT AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%stroke%'
),
-- Map MAP measurements to known stroke-admission pairs (for stroke rate calculation)
MAP_STROKE AS (
  SELECT
    m.map_category,
    m.subject_id,
    m.hadm_id,
    sp.subject_id AS stroke_subject
  FROM MAP_MEAS m
  LEFT JOIN STROKE_PAT sp
    ON m.subject_id = sp.subject_id
   AND m.hadm_id = sp.hadm_id
)
-- Part 3: aggregate per MAP category: patient counts and stroke rates
SELECT
  map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  SAFE_DIVIDE(COUNT(DISTINCT stroke_subject), COUNT(DISTINCT subject_id)) * 100 AS stroke_rate_percent
FROM MAP_STROKE
GROUP BY map_category
ORDER BY map_category;