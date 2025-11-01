WITH cohort AS (
  SELECT
    ie.stay_id,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
filtered_cohort AS (
  SELECT stay_id
  FROM cohort
  WHERE age_at_icu BETWEEN 80 AND 90
),
avg_heart_rates AS (
  SELECT
    fc.stay_id,
    AVG(ch.valuenum) AS avg_hr
  FROM filtered_cohort fc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch
    ON fc.stay_id = ch.stay_id
  WHERE ch.itemid = 220045
  GROUP BY fc.stay_id
)
SELECT
  (COUNTIF(avg_hr <= 110) * 100.0 / COUNT(*)) AS percentile
FROM avg_heart_rates;