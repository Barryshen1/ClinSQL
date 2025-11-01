WITH
-- 1. Female patients aged 41–51 who had an ICU stay
female_icu AS (
  SELECT
    p.subject_id,
    s.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`       AS p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays`  AS s
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
),

-- 2. Identify all MAP itemids in ICU
map_itemids AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%mean arterial pressure%'
),

-- 3. All MAP measurements for our cohort
map_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.valuenum AS map_mm_hg
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    JOIN female_icu AS f
      ON ce.subject_id = f.subject_id
     AND ce.hadm_id    = f.hadm_id
    JOIN map_itemids AS m
      ON ce.itemid = m.itemid
  WHERE
    ce.valuenum IS NOT NULL
),

-- 4. Stroke flag per admission
stroke_flag AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    1 AS stroke_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`    AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%stroke%'
  GROUP BY
    d.subject_id, d.hadm_id
),

-- 5. Combine MAP measurements with stroke flags and categorize MAP
map_with_flags AS (
  SELECT
    me.subject_id,
    me.hadm_id,
    CASE
      WHEN me.map_mm_hg < 65 THEN '<65'
      WHEN me.map_mm_hg BETWEEN 65 AND 74 THEN '65-74'
      WHEN me.map_mm_hg BETWEEN 75 AND 84 THEN '75-84'
      ELSE '>=85'
    END AS map_category,
    COALESCE(sf.stroke_flag, 0) AS stroke_flag
  FROM
    map_events AS me
    LEFT JOIN stroke_flag AS sf
      USING (subject_id, hadm_id)
)

-- 6. Final aggregation: per MAP category, distinct patient counts and stroke rates
SELECT
  map_category,
  COUNT(DISTINCT subject_id)                            AS patient_count,
  COUNT(DISTINCT CASE WHEN stroke_flag = 1 THEN subject_id END)
    AS stroke_patients,
  ROUND(
    100.0 * COUNT(DISTINCT CASE WHEN stroke_flag = 1 THEN subject_id END)
    / NULLIF(COUNT(DISTINCT subject_id), 0),
    1
  )                                                      AS stroke_rate_percent
FROM
  map_with_flags
GROUP BY
  map_category
ORDER BY
  -- order categories logically
  CASE
    WHEN map_category = '<65' THEN 1
    WHEN map_category = '65-74' THEN 2
    WHEN map_category = '75-84' THEN 3
    WHEN map_category = '>=85' THEN 4
  END;