WITH sbp_candidates AS (
  -- Max SBP in first 24h of each ICU stay for female patients aged 70-80
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id = i.hadm_id
   AND ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    -- SBP-related items
    AND LOWER(di.label) LIKE '%systolic%'
    -- first 24 hours after ICU intime
    AND ce.charttime >= i.intime
    AND ce.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY i.subject_id, i.hadm_id, i.stay_id
),
sbp_cat AS (
  -- categorize the maximum SBP per ICU stay
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.max_sbp,
    CASE
      WHEN s.max_sbp < 130 THEN '<130'
      WHEN s.max_sbp BETWEEN 130 AND 139 THEN '130-139'
      WHEN s.max_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN s.max_sbp >= 160 THEN '>=160'
      ELSE NULL
    END AS sbp_category
  FROM sbp_candidates s
  WHERE s.max_sbp IS NOT NULL
),
stroke_by_hadm AS (
  -- stroke flag per admission (hadm_id)
  SELECT di.hadm_id,
         MAX(CASE
               WHEN LOWER(dd.long_title) LIKE '%stroke%' THEN 1
               ELSE 0
             END) AS has_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),
sbp_with_stroke AS (
  -- Attach stroke flag to each ICU-stay (based on hadm_id)
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.max_sbp,
    c.sbp_category,
    COALESCE(s.has_stroke, 0) AS has_stroke
  FROM sbp_cat AS c
  LEFT JOIN stroke_by_hadm AS s
    ON s.hadm_id = c.hadm_id
)
, category_counts AS (
  -- Per-category counts and stroke rates
  SELECT
    sc.sbp_category AS category,
    COUNT(*) AS n_in_cat,
    AVG(has_stroke) AS stroke_rate
  FROM sbp_with_stroke AS sc
  GROUP BY sc.sbp_category
),
total_overall AS (
  SELECT SUM(n_in_cat) AS total FROM category_counts
)
SELECT
  cc.category,
  cc.n_in_cat,
  ROUND(100.0 * cc.n_in_cat / t.total, 2) AS pct_in_cohort,
  cc.stroke_rate AS stroke_rate
FROM category_counts cc
CROSS JOIN total_overall t
ORDER BY cc.category;