WITH temp_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    p.gender,
    p.anchor_age,
    ce.charttime,
    CASE
      WHEN di.itemid = 223762 THEN ce.valuenum
      WHEN di.itemid = 223761 THEN ce.valuenum * 9/5 + 32
    END AS temp_f
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE di.itemid IN (223761, 223762)
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND ce.charttime >= icu.intime
    AND ce.charttime <= icu.intime + INTERVAL 24 HOUR
)
SELECT
  APPROX_QUANTILES(temp_f, 100)[OFFSET(75)] AS temp_75th_percentile_F
FROM temp_events;