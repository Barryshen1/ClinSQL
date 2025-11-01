WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year BETWEEN 80 AND 90
),
spo2_aggregates AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE
    ce.itemid = 220277  -- SpO2 measurements
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
cohort_spo2 AS (
  SELECT
    c.stay_id,
    s.avg_spo2
  FROM cohort c
  INNER JOIN spo2_aggregates s
    ON c.stay_id = s.stay_id
)
SELECT
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) AS stays_below_88,
  ROUND(
    SAFE_DIVIDE(
      SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END),
      COUNT(*)
    ) * 100, 2
  ) AS percentile
FROM cohort_spo2;