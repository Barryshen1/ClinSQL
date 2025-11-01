WITH cohort AS (
  -- Select ICU stays for female patients aged 42-52
  SELECT
    icu.stay_id,
    icu.subject_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 42 AND 52
),
hr_itemids AS (
  -- Heart rate itemids (from d_items)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),
hr_per_stay AS (
  -- Compute per-stay average heart rate
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.stay_id = ce.stay_id
    JOIN hr_itemids hi
      ON ce.itemid = hi.itemid
  WHERE
    ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
)
SELECT
  COUNT(*) AS cohort_size,
  ROUND(100 * SUM(CASE WHEN avg_hr <= 90 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentile_90bpm
FROM
  hr_per_stay
WHERE
  avg_hr IS NOT NULL;