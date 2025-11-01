WITH target_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND (
      did.long_title LIKE '%acute pancreatitis%'
      OR d.icd_code IN ('577.0', 'K85.0', 'K85.1', 'K85.2', 'K85.3', 'K85.4', 'K85.5', 'K85.6', 'K85.8', 'K85.9')
    )
),

lab_instability AS (
  SELECT
    tc.subject_id,
    tc.hadm_id,
    COUNT(CASE WHEN le.flag IS NOT NULL AND le.flag != 'N' THEN 1 END) AS lab_instability_score,
    COUNT(*) AS total_labs_72h
  FROM target_cohort tc
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON tc.hadm_id = le.hadm_id
  WHERE le.charttime >= tc.admittime
    AND le.charttime <= DATETIME_ADD(tc.admittime, INTERVAL 72 HOUR)
  GROUP BY tc.subject_id, tc.hadm_id
),

p90_score AS (
  SELECT DISTINCT PERCENTILE_CONT(lab_instability_score, 0.9) OVER() AS p90_lab_instability
  FROM lab_instability
  LIMIT 1
),

high_risk_patients AS (
  SELECT
    li.subject_id,
    li.hadm_id,
    li.lab_instability_score,
    li.total_labs_72h,
    tc.hospital_expire_flag,
    DATETIME_DIFF(tc.dischtime, tc.admittime, HOUR) / 24.0 AS los_days
  FROM lab_instability li
  JOIN target_cohort tc ON li.subject_id = tc.subject_id AND li.hadm_id = tc.hadm_id
  CROSS JOIN p90_score
  WHERE li.lab_instability_score >= p90_score.p90_lab_instability
),

general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COUNT(CASE WHEN le.flag IS NOT NULL AND le.flag != 'N' THEN 1 END) AS lab_instability_score,
    COUNT(*) AS total_labs_72h,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le ON a.hadm_id = le.hadm_id
  WHERE le.charttime >= a.admittime
    AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
)

SELECT
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM high_risk_patients) AS mortality_rate_high_risk,
  (SELECT AVG(los_days) FROM high_risk_patients) AS mean_los_days_high_risk,
  (SELECT AVG(CAST(lab_instability_score AS FLOAT64) / total_labs_72h) FROM high_risk_patients WHERE total_labs_72h > 0) AS per_lab_critical_rate_high_risk,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM general_inpatients) AS mortality_rate_general,
  (SELECT AVG(los_days) FROM general_inpatients) AS mean_los_days_general,
  (SELECT AVG(CAST(lab_instability_score AS FLOAT64) / total_labs_72h) FROM general_inpatients WHERE total_labs_72h > 0) AS per_lab_critical_rate_general;