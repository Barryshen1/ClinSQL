WITH data AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'home'
      ELSE 'facility'
    END AS outcome
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.admission_type IN ('EMERGENCY', 'URGENT')
    AND FLOOR(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
    AND a.dischtime > a.admittime
)
SELECT 
  outcome,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75,
  AVG(CASE WHEN los <= 7 THEN 1.0 ELSE 0 END) * 100 AS percentile_rank_7day
FROM data
GROUP BY outcome
ORDER BY outcome;