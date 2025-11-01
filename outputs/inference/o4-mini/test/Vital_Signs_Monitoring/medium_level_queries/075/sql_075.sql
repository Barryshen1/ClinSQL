WITH cohort AS (
  -- Male patients aged 56-66 with ICU stays
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
),

map_per_stay AS (
  -- Compute mean MAP per stay using itemid = 52
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM
    cohort c
    -- join to icustays to get intime/outtime
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i2
      ON c.stay_id = i2.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.subject_id = ce.subject_id
     AND c.hadm_id    = ce.hadm_id
     AND c.stay_id    = ce.stay_id
     AND ce.itemid = 52
     AND ce.valuenum IS NOT NULL
     AND ce.charttime BETWEEN i2.intime AND i2.outtime
  GROUP BY
    c.stay_id
),

stroke_flags AS (
  -- Flag admissions with any stroke diagnosis (ICD9 codes 430-438)
  SELECT
    hadm_id,
    1 AS stroke_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.icd_code LIKE '43%'
  GROUP BY
    hadm_id
)

SELECT
  CASE
    WHEN m.mean_map < 65 THEN '<65'
    WHEN m.mean_map BETWEEN 65 AND 74 THEN '65-74'
    WHEN m.mean_map BETWEEN 75 AND 84 THEN '75-84'
    ELSE '>=85'
  END AS map_category,
  COUNT(*) AS stay_count,
  SUM(IF(sf.stroke_flag = 1, 1, 0)) AS stroke_count,
  ROUND(SUM(IF(sf.stroke_flag = 1, 1, 0)) / COUNT(*), 3) AS stroke_rate
FROM
  map_per_stay m
  JOIN cohort c
    ON m.stay_id = c.stay_id
  LEFT JOIN stroke_flags sf
    ON c.hadm_id = sf.hadm_id
GROUP BY
  map_category
ORDER BY
  CASE
    WHEN map_category = '<65' THEN 1
    WHEN map_category = '65-74' THEN 2
    WHEN map_category = '75-84' THEN 3
    WHEN map_category = '>=85' THEN 4
  END;