WITH cohort AS (
  SELECT ie.stay_id
  FROM physionet-data.mimiciv_3_1_icu.icustays ie
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
spo2_averages AS (
  SELECT ce.stay_id, AVG(ce.valuenum) AS avg_spo2
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN cohort c
    ON ce.stay_id = c.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE di.label = 'SpO2'
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
percentile_calc AS (
  SELECT
    COUNTIF(avg_spo2 <= 88) AS n_leq_88,
    COUNT(*) AS total_stays
  FROM spo2_averages
)
SELECT
  CASE
    WHEN total_stays > 0 THEN 100.0 * n_leq_88 / total_stays
    ELSE NULL
  END AS percentile
FROM percentile_calc;