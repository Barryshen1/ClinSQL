SELECT 
  SUM(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile
FROM (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS mean_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON ce.stay_id = ie.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label = 'SpO2'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime < ie.intime + INTERVAL 24 HOUR
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
  GROUP BY ie.stay_id
) AS patient_means;