WITH icu_patients AS (
  SELECT
    i.stay_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    i.intime,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu_admission
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 52 AND 62
),
first_map AS (
  SELECT
    c.stay_id,
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_patients ip
  ON
    c.stay_id = ip.stay_id
  WHERE
    c.itemid = 52
    AND c.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(valuenum, 0.25) OVER () AS q1,
  PERCENTILE_CONT(valuenum, 0.75) OVER () AS q3,
  PERCENTILE_CONT(valuenum, 0.75) OVER () - PERCENTILE_CONT(valuenum, 0.25) OVER () AS iqr
FROM
  first_map
WHERE
  rn = 1
LIMIT 1;