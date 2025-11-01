WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),
sbp_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%systolic%'
),
max_sbp AS (
  SELECT
    c.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM
    cohort AS c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON c.stay_id = ce.stay_id
  JOIN
    sbp_items AS si
    ON ce.itemid = si.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime 
                         AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY
    c.stay_id
),
stroke_hadm AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%stroke%'
),
combined AS (
  SELECT
    m.stay_id,
    m.max_sbp,
    CASE
      WHEN m.max_sbp < 130 THEN '<130'
      WHEN m.max_sbp BETWEEN 130 AND 139 THEN '130-139'
      WHEN m.max_sbp BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category,
    CASE
      WHEN sh.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS stroke_flag
  FROM
    max_sbp AS m
  JOIN
    cohort AS c
    ON m.stay_id = c.stay_id
  LEFT JOIN
    stroke_hadm AS sh
    ON c.hadm_id = sh.hadm_id
),
agg AS (
  SELECT
    sbp_category,
    COUNT(*) AS n_in_category,
    SUM(stroke_flag) AS n_stroke_in_category
  FROM
    combined
  GROUP BY
    sbp_category
),
tot AS (
  SELECT
    COUNT(*) AS total_cohort
  FROM
    combined
)
SELECT
  a.sbp_category,
  a.n_in_category,
  ROUND( a.n_in_category / t.total_cohort * 100, 1 ) AS pct_of_cohort,
  a.n_stroke_in_category,
  ROUND( a.n_stroke_in_category / a.n_in_category * 100, 1 ) AS stroke_rate
FROM
  agg AS a
CROSS JOIN
  tot AS t
ORDER BY
  -- maintain the desired SBP order
  CASE
    WHEN sbp_category = '<130' THEN 1
    WHEN sbp_category = '130-139' THEN 2
    WHEN sbp_category = '140-159' THEN 3
    WHEN sbp_category = '>=160' THEN 4
  END;