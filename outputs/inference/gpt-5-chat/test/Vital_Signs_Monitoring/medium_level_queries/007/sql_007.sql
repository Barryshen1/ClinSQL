WITH female_elderly_icu AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
),
spo2_events AS (
  SELECT ce.stay_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN female_elderly_icu AS cohort
    ON ce.stay_id = cohort.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND (
      LOWER(di.label) LIKE '%spo2%' OR
      LOWER(di.label) LIKE '%o2 saturation%'
    )
),
avg_spo2_per_stay AS (
  SELECT stay_id, AVG(valuenum) AS avg_spo2
  FROM spo2_events
  GROUP BY stay_id
),
percentile_result AS (
  SELECT
    COUNTIF(avg_spo2 <= 88) / COUNT(*) * 100 AS percentile
  FROM avg_spo2_per_stay
)
SELECT percentile
FROM percentile_result;