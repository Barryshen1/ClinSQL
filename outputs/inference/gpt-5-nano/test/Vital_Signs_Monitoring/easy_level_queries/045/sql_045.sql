WITH resp_events AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.hadm_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.stay_id = ce.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND (
      LOWER(di.label) LIKE '%respiratory rate%' OR
      LOWER(di.label) LIKE '%resp rate%'
    )
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
),
first_rate_per_stay AS (
  SELECT
    subject_id,
    stay_id,
    hadm_id,
    charttime,
    valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY stay_id
      ORDER BY charttime
    ) AS rn
  FROM resp_events
)
SELECT
  STDDEV_SAMP(valuenum) AS sd_first_respir_rate
FROM first_rate_per_stay
WHERE rn = 1
  AND subject_id IN (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'Male'
      AND anchor_age BETWEEN 51 AND 61
  );