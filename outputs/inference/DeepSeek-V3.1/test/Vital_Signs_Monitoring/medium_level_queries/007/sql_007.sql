WITH spo2_avg_per_stay AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON ce.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    ce.itemid = 220277  -- SpO2
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
  GROUP BY ie.stay_id
),
percentile_calc AS (
  SELECT
    COUNT(*) AS total_stays,
    SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) AS stays_below_88,
    100.0 * SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) / COUNT(*) AS percentile
  FROM spo2_avg_per_stay
)
SELECT 
  total_stays,
  stays_below_88,
  percentile
FROM percentile_calc;