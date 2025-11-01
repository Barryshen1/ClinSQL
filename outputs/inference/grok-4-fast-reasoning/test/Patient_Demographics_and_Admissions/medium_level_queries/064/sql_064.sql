WITH total_icu AS (
  SELECT 
    hadm_id, 
    SUM(los) AS los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
)
SELECT 
  outcome,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  AVG(CASE WHEN los <= 10 THEN 1.0 ELSE 0 END) * 100 AS percent_le_10_days
FROM (
  SELECT 
    a.hadm_id,
    i.los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(a.discharge_location) IN ('home', 'home health care') THEN 'home'
      ELSE NULL 
    END AS outcome
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN total_icu i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
) 
WHERE outcome IS NOT NULL
GROUP BY outcome
ORDER BY n DESC;