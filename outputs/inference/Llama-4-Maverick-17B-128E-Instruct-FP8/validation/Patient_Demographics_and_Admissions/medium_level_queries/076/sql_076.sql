WITH patient_age AS (
  SELECT p.subject_id, p.gender, 
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
         a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' 
  AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 83 AND 93
),
patient_los AS (
  SELECT hadm_id, 
         DATETIME_DIFF(dischtime, admittime, DAY) AS los,
         CASE WHEN hospital_expire_flag = 1 THEN 'Dead' ELSE 'Alive' END AS discharge_status
  FROM patient_age
)
SELECT discharge_status,
       AVG(los) AS mean_los,
       APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
       APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
       APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
       SUM(CASE WHEN los <= 5 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percentile_rank_5day
FROM patient_los
GROUP BY discharge_status;