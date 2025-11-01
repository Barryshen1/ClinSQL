WITH septic_shock AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_code = 'R65.21' AND di.icd_version = 10
),

patients_with_septic_shock AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN septic_shock s ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 63 AND 73
),

diagnosis_count AS (
  SELECT hadm_id, COUNT(*) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

cohort AS (
  SELECT pss.*, dc.num_diagnoses
  FROM patients_with_septic_shock pss
  JOIN diagnosis_count dc ON pss.hadm_id = dc.hadm_id
  WHERE dc.num_diagnoses > 15
),

drg_severity_cohort AS (
  SELECT c.*, d.drg_severity
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` d 
    ON c.hadm_id = d.hadm_id AND d.drg_type = 'primary'
),

cohort_complication_rate AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN d.long_title LIKE '%complication%' THEN c.hadm_id END) * 100.0 / NULLIF(COUNT(DISTINCT c.hadm_id), 0) AS complication_rate
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON c.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
),

cohort_survivor_los AS (
  SELECT AVG(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY)) AS avg_los
  FROM cohort
  WHERE hospital_expire_flag = 0
),

general_inpatients AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

general_complication_rate AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN d.long_title LIKE '%complication%' THEN g.hadm_id END) * 100.0 / NULLIF(COUNT(DISTINCT g.hadm_id), 0) AS complication_rate
  FROM general_inpatients g
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON g.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
),

general_survivor_los AS (
  SELECT AVG(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY)) AS avg_los
  FROM general_inpatients
  WHERE hospital_expire_flag = 0
),

ninety_day_mortality AS (
  SELECT 
    AVG(CASE WHEN dod IS NOT NULL AND dod <= DATE_ADD(DATE(admittime), INTERVAL 90 DAY) THEN 1 ELSE 0 END) AS mortality_rate
  FROM drg_severity_cohort
),

mean_risk_score AS (
  SELECT AVG(drg_severity) AS mean_risk_score
  FROM drg_severity_cohort
  WHERE drg_severity IS NOT NULL
),

specific_profile_risk_scores AS (
  SELECT drg_severity
  FROM drg_severity_cohort
  WHERE anchor_age = 68 AND gender = 'M' AND num_diagnoses = 16
),

percentile_calc AS (
  SELECT 
    (COUNT(CASE WHEN c.drg_severity <= sp.drg_severity THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0)) AS percentile
  FROM drg_severity_cohort c
  CROSS JOIN specific_profile_risk_scores sp
)

SELECT 
  (SELECT mean_risk_score FROM mean_risk_score) AS mean_risk_score,
  (SELECT mortality_rate FROM ninety_day_mortality) AS ninety_day_mortality,
  (SELECT complication_rate FROM cohort_complication_rate) AS cohort_complication_rate,
  (SELECT avg_los FROM cohort_survivor_los) AS cohort_survivor_los,
  (SELECT complication_rate FROM general_complication_rate) AS general_complication_rate,
  (SELECT avg_los FROM general_survivor_los) AS general_survivor_los,
  (SELECT percentile FROM percentile_calc) AS percentile_for_profile;