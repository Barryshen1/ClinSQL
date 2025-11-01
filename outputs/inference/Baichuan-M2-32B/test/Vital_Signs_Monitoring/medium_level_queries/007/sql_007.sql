WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
avg_spo2_per_stay AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM
    cohort c
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220277  -- SpO2 itemid
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100  -- Valid SpO2 range
  GROUP BY
    c.stay_id
  HAVING
    COUNT(*) > 0  -- Ensure at least one measurement
),
all_stays AS (
  SELECT
    stay_id,
    avg_spo2
  FROM
    avg_spo2_per_stay
),
summary AS (
  SELECT
    COUNT(*) AS total_stays,
    COUNTIF(avg_spo2 <= 88) AS count_below_or_equal,
    (COUNTIF(avg_spo2 <= 88) * 100.0) / NULLIF(COUNT(*), 0) AS percentile_88
  FROM
    all_stays
)
SELECT
  percentile_88
FROM
  summary
WHERE
  total_stays > 0;