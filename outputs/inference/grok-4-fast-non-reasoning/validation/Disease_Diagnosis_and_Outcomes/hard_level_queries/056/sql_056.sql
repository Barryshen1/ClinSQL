WITH patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 63 AND 73
),
admissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
diagnosis_counts AS (
  SELECT subject_id, hadm_id, COUNT(DISTINCT icd_code) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE CAST(icd_version AS STRING) = 'ICD-10'
  GROUP BY subject_id, hadm_id
),
septic_diagnoses AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE CAST(icd_version AS STRING) = 'ICD-10' AND icd_code = 'R6521'  -- Septic shock
),
procedures AS (
  SELECT subject_id, hadm_id, COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE CAST(icd_version AS STRING) = 'ICD-10'
  GROUP BY subject_id, hadm_id
),
drg_risk AS (
  SELECT d.subject_id, d.hadm_id, SAFE_CAST(dr.drg_mortality AS INT64) AS risk_score
  FROM diagnosis_counts d
  JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dr ON d.hadm_id = dr.hadm_id
  WHERE dr.drg_type = 'MS-DRG'  -- MS-DRG
),
cohort_septic AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, dc.num_diagnoses,
         COALESCE(pr.num_procedures, 0) > 0 AS has_complication,
         dr.risk_score,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
         a.hospital_expire_flag,
         a.admittime,
         pat.dod
  FROM patients p
  JOIN admissions a ON p.subject_id = a.subject_id
  JOIN diagnosis_counts dc ON a.hadm_id = dc.hadm_id
  JOIN septic_diagnoses sd ON a.hadm_id = sd.hadm_id
  LEFT JOIN procedures pr ON a.hadm_id = pr.hadm_id
  LEFT JOIN drg_risk dr ON a.hadm_id = dr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON p.subject_id = pat.subject_id
  WHERE dc.num_diagnoses > 15
),
cohort_general AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age,
         dc.num_diagnoses,
         COALESCE(pr.num_procedures, 0) > 0 AS has_complication,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
         a.hospital_expire_flag,
         a.admittime,
         pat.dod
  FROM patients p
  JOIN admissions a ON p.subject_id = a.subject_id
  JOIN diagnosis_counts dc ON a.hadm_id = dc.hadm_id
  LEFT JOIN procedures pr ON a.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON p.subject_id = pat.subject_id
  WHERE dc.num_diagnoses > 15
),
mortality_septic AS (
  SELECT COUNT(DISTINCT subject_id) AS total_subjects,
         COUNTIF(DATE_DIFF(COALESCE(dod, dischtime), admittime, DAY) <= 90 
                 AND (hospital_expire_flag = 1 OR dod IS NOT NULL)) AS deaths_90d
  FROM cohort_septic
),
survivor_los_septic AS (
  SELECT AVG(los) AS mean_los_survivors
  FROM cohort_septic
  WHERE hospital_expire_flag = 0 AND dod IS NULL
),
complication_septic AS (
  SELECT AVG(CAST(has_complication AS FLOAT64)) * 100 AS complication_rate_pct
  FROM cohort_septic
),
risk_septic AS (
  SELECT AVG(risk_score) AS mean_risk_score
  FROM cohort_septic
),
complication_general AS (
  SELECT AVG(CAST(has_complication AS FLOAT64)) * 100 AS complication_rate_pct
  FROM cohort_general
),
survivor_los_general AS (
  SELECT AVG(los) AS mean_los_survivors
  FROM cohort_general
  WHERE hospital_expire_flag = 0 AND dod IS NULL
),
profile_complications AS (
  SELECT has_complication,
         PERCENT_RANK() OVER (ORDER BY CAST(has_complication AS INT64)) AS complication_percentile
  FROM cohort_septic
  WHERE num_diagnoses >= 16
)
SELECT 
  (SELECT mean_risk_score FROM risk_septic) AS mean_risk_score_septic,
  (SELECT deaths_90d * 100.0 / total_subjects FROM mortality_septic) AS mortality_90d_pct_septic,
  (SELECT complication_rate_pct FROM complication_septic) AS complication_rate_pct_septic,
  (SELECT mean_los_survivors FROM survivor_los_septic) AS mean_los_survivors_septic,
  (SELECT complication_rate_pct FROM complication_general) AS complication_rate_pct_general,
  (SELECT mean_los_survivors FROM survivor_los_general) AS mean_los_survivors_general,
  (SELECT AVG(complication_percentile) FROM profile_complications) * 100 AS profile_complication_percentile
;