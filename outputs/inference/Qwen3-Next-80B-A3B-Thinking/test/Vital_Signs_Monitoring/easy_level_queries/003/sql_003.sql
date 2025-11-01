WITH filtered_stays AS (
  SELECT
    i.stay_id,
    p.anchor_age,
    p.anchor_year,
    i.intime,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 40 AND 50
),
mean_hr_per_stay AS (
  SELECT
    fs.stay_id,
    AVG(c.valuenum) AS mean_hr
  FROM
    filtered_stays fs
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON
    fs.stay_id = c.stay_id
  WHERE
    c.itemid = 220045  -- Heart Rate
    AND c.valuenum IS NOT NULL
  GROUP BY
    fs.stay_id
)
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mean_hr) AS median_mean_hr
FROM
  mean_hr_per_stay;