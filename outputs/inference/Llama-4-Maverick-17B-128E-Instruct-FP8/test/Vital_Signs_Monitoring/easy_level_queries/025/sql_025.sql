WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 39 AND 49
),
respiratory_rate_stays AS (
  SELECT ie.stay_id, AVG(ce.valuenum) AS mean_rr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  INNER JOIN filtered_patients fp ON ie.subject_id = fp.subject_id
  WHERE ce.itemid = 220210
  GROUP BY ie.stay_id
)
SELECT APPROX_QUANTILES(mean_rr, 100)[OFFSET(75)] AS percentile_75th
FROM respiratory_rate_stays;