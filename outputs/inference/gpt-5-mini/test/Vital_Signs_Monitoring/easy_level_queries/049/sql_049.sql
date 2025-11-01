WITH map_measurements AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = icu.stay_id
       AND ce.subject_id = icu.subject_id
       AND ce.hadm_id = icu.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300
    -- identify recorded mean arterial pressure items by label
    AND (
      REGEXP_CONTAINS(LOWER(di.label), r'mean')
      AND REGEXP_CONTAINS(LOWER(di.label), r'blood|arterial|pressure|bp')
    )
),

per_stay_mean AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(valuenum) AS mean_map_first24h,
    COUNT(*) AS n_obs
  FROM map_measurements
  GROUP BY stay_id, subject_id, hadm_id
  HAVING n_obs >= 1
)

SELECT
  STDDEV_SAMP(mean_map_first24h) AS sd_first24h_mean_map,
  COUNT(*) AS n_stays_included
FROM per_stay_mean;