WITH
  -- First, identify all average SpO2 values per ICU stay
  spo2_averages AS (
    SELECT
      ce.stay_id,
      AVG(ce.valuenum) AS avg_spo2
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE
      -- itemid for SpO2. From d_items, 220277 is 'SpO2'.
      ce.itemid = 220277
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0
      AND ce.valuenum <= 100 -- Filter for physiologically plausible SpO2 values
    GROUP BY
      ce.stay_id
  ),
  -- Next, filter for the specific cohort: female ICU patients, age 80-90
  cohort_icustays AS (
    SELECT
      ic.stay_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON p.subject_id = adm.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` ic
      ON adm.hadm_id = ic.hadm_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 80 AND 90
  )
-- Finally, join the cohort with SpO2 averages and calculate the percentile
SELECT
  (
    COUNT(CASE WHEN sa.avg_spo2 <= 88.0 THEN 1 END) * 100.0
  ) / COUNT(sa.avg_spo2) AS percentile_at_88_avg_spo2
FROM
  cohort_icustays cis
INNER JOIN
  spo2_averages sa
  ON cis.stay_id = sa.stay_id;