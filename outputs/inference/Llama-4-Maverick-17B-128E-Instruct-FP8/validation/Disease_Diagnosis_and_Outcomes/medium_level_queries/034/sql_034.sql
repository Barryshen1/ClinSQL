WITH heart_failure_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.icd_version = 10 AND lower(diag.long_title) LIKE '%heart failure%'
),
patient_info AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 70 AND 80
  AND a.hadm_id IN (SELECT hadm_id FROM heart_failure_patients)
),
mortality_rates AS (
  SELECT 
    CASE WHEN los < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
    COUNT(*) AS N,
    SUM(hospital_expire_flag) AS deaths
  FROM patient_info
  GROUP BY CASE WHEN los < 8 THEN '<8 days' ELSE '>=8 days' END
),
time_to_death AS (
  SELECT 
    CASE WHEN los < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
    TIMESTAMP_DIFF(deathtime, admittime, HOUR) AS time_to_death_hours
  FROM patient_info
  WHERE hospital_expire_flag = 1
),
median_time_to_death AS (
  SELECT los_group, APPROX_QUANTILES(time_to_death_hours, 100)[OFFSET(50)] AS median_time_to_death_hours
  FROM time_to_death
  GROUP BY los_group
)
SELECT 
  mr.los_group,
  mr.N,
  SAFE_DIVIDE(mr.deaths, mr.N) * 100 AS mortality_rate,
  mttd.median_time_to_death_hours
FROM mortality_rates mr
LEFT JOIN median_time_to_death mttd
ON mr.los_group = mttd.los_group;