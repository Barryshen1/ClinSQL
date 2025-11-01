WITH sbp_measurements AS (
  SELECT 
    ie.stay_id,
    ce.valuenum AS sbp_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON ce.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND di.label IN (
      'Systolic BP', 'Arterial BP Systolic', 'BP Systolic', 'Systolic BP (NIBP)', 
      'Systolic BP (Invasive)', 'Systolic BP (Arterial)', 'Systolic BP (Non-Invasive)'
    )
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 50 AND ce.valuenum < 300  -- reasonable physiological range
    AND ce.charttime >= ie.intime
    AND ce.charttime <= TIMESTAMP_ADD(ie.intime, INTERVAL 48 HOUR)
),
per_stay_averages AS (
  SELECT 
    stay_id,
    AVG(sbp_value) AS avg_sbp_per_stay
  FROM sbp_measurements
  GROUP BY stay_id
  HAVING AVG(sbp_value) IS NOT NULL
)
SELECT 
  SAFE_DIVIDE(COUNTIF(avg_sbp_per_stay <= 150) * 100.0, COUNT(*)) AS percentile_of_150
FROM per_stay_averages;