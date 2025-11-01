WITH hr_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
),
cohort AS (
  SELECT
    ie.stay_id,
    ie.subject_id,
    AVG(ce.valuenum) AS avg_hr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  JOIN hr_itemids h
    ON ce.itemid = h.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 AND ce.valuenum < 300
  GROUP BY ie.stay_id, ie.subject_id
),
stats AS (
  SELECT
    COUNT(*) AS cohort_size,
    COUNTIF(avg_hr <= 90) AS num_leq_90
  FROM cohort
)
SELECT
  cohort_size,
  num_leq_90,
  ROUND(100 * num_leq_90 / cohort_size, 2) AS percentile_90bpm
FROM stats;