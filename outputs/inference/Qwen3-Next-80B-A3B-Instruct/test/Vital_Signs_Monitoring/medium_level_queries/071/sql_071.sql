WITH female_icu_stays AS (
  SELECT i.stay_id
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
spo2_measurements AS (
  SELECT 
    c.stay_id,
    c.valuenum AS spo2_value
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE d.label = 'SpO2'
    AND c.valuenum BETWEEN 50 AND 100
),
per_stay_mean_spo2 AS (
  SELECT 
    f.stay_id,
    AVG(s.spo2_value) AS mean_spo2
  FROM female_icu_stays f
  INNER JOIN spo2_measurements s
    ON f.stay_id = s.stay_id
  GROUP BY f.stay_id
)
SELECT 
  (SUM(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile
FROM per_stay_mean_spo2;