WITH icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.los, a.discharge_location, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
filtered_patients AS (
  SELECT p.subject_id, ic.hadm_id, ic.stay_id, ic.los, 
         CASE 
           WHEN ic.discharge_location = 'HOME' THEN 'Home'
           WHEN ic.discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
           WHEN ic.hospital_expire_flag = 1 THEN 'In-hospital death'
           ELSE 'Other'
         END AS discharge_outcome
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN icu_stays ic ON p.subject_id = ic.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 63 AND 73
)
SELECT 
  discharge_outcome,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_le_10_days
FROM filtered_patients
WHERE discharge_outcome IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY discharge_outcome
ORDER BY discharge_outcome;