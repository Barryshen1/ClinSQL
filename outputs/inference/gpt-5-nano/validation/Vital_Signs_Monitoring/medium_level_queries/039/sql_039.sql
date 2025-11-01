WITH MAP_MEASUREMENTS AS (
  SELECT
    ios.stay_id,
    AVG(ce.valuenum) AS map_avg,
    COUNT(ce.valuenum) AS n_meas
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ios
    ON ce.hadm_id = ios.hadm_id
   AND ce.stay_id = ios.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON ios.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= ios.intime
    AND ce.charttime <= TIMESTAMP_ADD(ios.intime, INTERVAL 48 HOUR)
    AND (LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%')
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND ce.valuenum IS NOT NULL
  GROUP BY ios.stay_id
  HAVING COUNT(ce.valuenum) >= 3
)
SELECT
  SAFE_DIVIDE(SUM(CASE WHEN map_avg <= 60 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS percentile_60
FROM MAP_MEASUREMENTS;