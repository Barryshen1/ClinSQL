WITH rr_events AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE di.label = 'Respiratory Rate'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime BETWEEN icu.intime
                         AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
)
, min_per_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    MIN(valuenum) AS min_resp_rate_24h
  FROM rr_events
  GROUP BY subject_id, hadm_id, stay_id
)
SELECT
  MIN(min_resp_rate_24h) AS overall_min_resp_rate_24h
FROM min_per_stay;