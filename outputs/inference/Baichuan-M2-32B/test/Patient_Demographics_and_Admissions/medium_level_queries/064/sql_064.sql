WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 63 AND 73
),
icu_stays_with_adm AS (
  SELECT 
    i.stay_id,
    i.los,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN filtered_patients p ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),
outcomes AS (
  SELECT 
    stay_id,
    los,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOSPICE' THEN 'hospice'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
      ELSE NULL
    END AS outcome
  FROM icu_stays_with_adm
)
SELECT 
  outcome,
  COUNT(stay_id) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  (COUNTIF(los <= 10) * 100.0) / COUNT(stay_id) AS percent_le_10
FROM outcomes
WHERE outcome IS NOT NULL
GROUP BY outcome
ORDER BY outcome;