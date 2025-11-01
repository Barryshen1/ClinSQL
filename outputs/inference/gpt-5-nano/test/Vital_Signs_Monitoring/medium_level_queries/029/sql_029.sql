WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items` AS di
  WHERE LOWER(di.label) LIKE '%spo2%'
),

-- 2) Compute mean SpO2 in first 24 hours for each icustay, restricted to male patients aged 73-83
cohort AS (
  SELECT
    pat.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    AVG(ce.valuenum) AS mean_spo2_24h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id = i.hadm_id
  JOIN spo2_items AS si
    ON ce.itemid = si.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = i.subject_id
  WHERE ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 73 AND 83
  GROUP BY pat.subject_id, i.hadm_id, i.stay_id, i.intime
  HAVING COUNT(ce.valuenum) > 0
)

-- 3) Compute the percentile of 92 within the distribution of mean_spo2_24h
SELECT
  100.0 * SUM(CASE WHEN mean_spo2_24h <= 92 THEN 1 ELSE 0 END) / COUNT(*) AS spo2_92_percentile
FROM cohort;