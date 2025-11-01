with Home Care', 'Home with Services') THEN 'home'
    WHEN a.discharge_location IN ('SNF', 'Rehab', 'LTACH') THEN 'SNF/rehab/LTACH'
    WHEN a.discharge_location = 'Expired' THEN 'in-hospital mortality'
  END AS discharge_category,
  COUNT(*) AS n,
  AVG(i.los) AS mean_los,
  PERCENTILE_CONT(i.los, 0.25) AS p25_los,
  PERCENTILE_CONT(i.los, 0.5) AS median_los,
  PERCENTILE_CONT(i.los, 0.75) AS p75_los,
  PERCENTILE_CONT(i.los, 0.90) AS p90_los,
  PERCENTILE_CONT(i.los, 0.95) AS p95_los,
  100 * AVG(CASE WHEN i.los <= 5 THEN 1.0 ELSE 0 END) AS percentile_rank_5day
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON i.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON i.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 37 AND 47
  AND i.first_careunit LIKE '%ICU%'
  AND a.admission_location != 'ICU'
  AND a.discharge_location IN ('Home', 'Home with Home Care', 'Home with Services', 'SNF', 'Rehab', 'LTACH', 'Expired')
GROUP BY discharge_category
ORDER BY discharge_category;