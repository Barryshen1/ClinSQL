WITH cohort AS (
  SELECT
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 42 AND 52
),
avg_hr AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid = 211
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
)
SELECT
  COUNT(*) AS cohort_size,
  (COUNTIF(avg_hr <= 90) * 100.0) / COUNT(*) AS percentile
FROM
  avg_hr;