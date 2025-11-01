WITH surgical_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.services`
  WHERE curr_service IN ('CSURG', 'NSURG', 'ORTHO', 'PSURG', 'SURG', 'TSURG', 'VSURG')
), cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    AND a.hadm_id IN (SELECT hadm_id FROM surgical_admissions)
), cohort_los AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM cohort
)
SELECT
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
    WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOME WITH HOME IV PROVIDR') THEN 'Discharged home'
    ELSE 'Discharged to facility'
  END AS discharge_group,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days,
  100.0 * COUNTIF(los_days <= 7) / COUNT(*) AS pct_los_leq_7
FROM cohort_los
GROUP BY discharge_group
ORDER BY 
  CASE discharge_group
    WHEN 'Discharged home' THEN 1
    WHEN 'Discharged to facility' THEN 2
    WHEN 'In-hospital mortality' THEN 3
  END;