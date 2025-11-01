WITH spo2_events AS (
  SELECT
    p.subject_id,
    icu.stay_id,
    icu.intime,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE di.label LIKE '%SpO2%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND ce.charttime BETWEEN icu.intime
                         AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
),
mean_spo2_per_stay AS (
  SELECT
    subject_id,
    stay_id,
    AVG(valuenum) AS mean_spo2
  FROM spo2_events
  GROUP BY subject_id, stay_id
),
percentile_calc AS (
  SELECT
    COUNTIF(mean_spo2 <= 92) / COUNT(*) * 100 AS percentile_92
  FROM mean_spo2_per_stay
)
SELECT percentile_92
FROM percentile_calc;