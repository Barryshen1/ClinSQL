WITH cohort AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
),
first_spo2 AS (
  SELECT
    c.subject_id,
    c.stay_id,
    MIN_BY(ce.valuenum, ce.charttime) AS first_spo2_value
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.stay_id = ce.stay_id
  JOIN spo2_items di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
  GROUP BY c.subject_id, c.stay_id
),
quartiles AS (
  SELECT
    APPROX_QUANTILES(first_spo2_value, 4) AS qs
  FROM first_spo2
)
SELECT
  qs[3] - qs[1] AS iqr_spo2
FROM quartiles;