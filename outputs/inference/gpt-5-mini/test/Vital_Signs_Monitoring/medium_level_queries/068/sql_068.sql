WITH map_items AS (
  -- Identify candidate MAP itemids in ICU d_items by text match
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (
    LOWER(label) LIKE '%mean arterial%'
    OR LOWER(label) LIKE '%map%'
    OR LOWER(abbreviation) LIKE '%map%'
    OR LOWER(label) LIKE '%arterial pressure, mean%'
  )
),

eligible_stays AS (
  -- ICU stays for female patients aged 41-51
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
),

hadm_stroke_flag AS (
  -- Flag admissions with a stroke-related diagnosis (text-match on long_title)
  SELECT
    d.hadm_id,
    d.subject_id,
    MAX(
      CASE
        WHEN LOWER(di.long_title) LIKE '%stroke%' THEN 1
        WHEN LOWER(di.long_title) LIKE '%cerebrovascular%' THEN 1
        WHEN LOWER(di.long_title) LIKE '%cva%' THEN 1
        WHEN LOWER(di.long_title) LIKE '%cerebral infarction%' THEN 1
        ELSE 0
      END
    ) AS had_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  GROUP BY d.hadm_id, d.subject_id
),

map_measurements AS (
  -- MAP measurements (valuenum) during eligible ICU stays
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS map_val,
    CASE
      WHEN ce.valuenum IS NULL THEN NULL
      WHEN ce.valuenum < 65 THEN '<65'
      WHEN ce.valuenum >= 65 AND ce.valuenum < 75 THEN '65-74'
      WHEN ce.valuenum >= 75 AND ce.valuenum < 85 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  JOIN eligible_stays es
    ON ce.stay_id = es.stay_id
    AND ce.subject_id = es.subject_id
    -- Keep only numeric values
  WHERE ce.valuenum IS NOT NULL
),

-- For each (subject_id, hadm_id, map_category) identify if they belong to that category and whether their admission had stroke
subject_category_flags AS (
  SELECT
    m.map_category,
    m.subject_id,
    m.hadm_id,
    MAX(CASE WHEN hsf.had_stroke = 1 THEN 1 ELSE 0 END) AS had_stroke_in_hadm
  FROM map_measurements m
  LEFT JOIN hadm_stroke_flag hsf
    ON m.hadm_id = hsf.hadm_id
    AND m.subject_id = hsf.subject_id
  GROUP BY m.map_category, m.subject_id, m.hadm_id
)

SELECT
  map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN had_stroke_in_hadm = 1 THEN subject_id END) AS stroke_count,
  ROUND(
    100.0 * COUNT(DISTINCT CASE WHEN had_stroke_in_hadm = 1 THEN subject_id END)
    / NULLIF(COUNT(DISTINCT subject_id), 0),
    2
  ) AS stroke_rate_pct,
  -- optional: total number of MAP measurements that fell into each category
  (SELECT COUNT(*) FROM map_measurements mm WHERE mm.map_category = scf.map_category) AS measurement_count
FROM subject_category_flags scf
GROUP BY map_category
ORDER BY
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
    ELSE 5
  END;