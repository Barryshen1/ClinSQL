with "with spaces must be enclosed in backticks." — this is not valid SQL and was mistakenly included as part of the SQL code.
- BigQuery attempted to parse this comment as SQL, failing when it encountered the word "must" after "with spaces".
- The fix is to remove all non-SQL explanatory text before the `WITH` clause. Only valid SQL should be present.
- Additionally, the `comorbidity_codes` CTE was incomplete — it ended with `UNION ALL` followed by a semicolon, which is invalid. The last `UNION ALL` should not be followed by another `UNION ALL` or be incomplete.
- We complete the `comorbidity_codes` list with proper entries and ensure all `UNION ALL` statements are correctly structured.
- We proceed to compute comorbidity counts per patient, assign quartiles, identify the top quartile, and compute outcomes: 30-day mortality, cardiac complications (MI, arrhythmia, heart failure), neurologic complications (stroke, seizure), and median survival days.
- We calculate survival days as the time from admission to death within 30 days, or 30 days if the patient survived beyond that or was discharged.
- Finally, we compute the comorbidity count for the cohort and determine the percentile of a representative 84-year-old male (we assume we are summarizing the cohort, and the "his" refers to a patient within this group).

Key changes:
- Remove all non-SQL comments from the query body.
- Fix invalid CTE syntax and complete the `comorbidity_codes` list.
- Compute comorbidity burden per patient.
- Define top quartile using `PERCENTILE_CONT` or `NTILE`.
- Compute all requested outcomes.

sql
WITH diagnoses_with_age AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.dod,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) AS admitty,
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON di.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%pulmonary embolism%'
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89
),
-- Get distinct patients with PE in the age/gender group
pe_patients AS (
  SELECT DISTINCT
    subject_id,
    gender,
    age_at_admit,
    admittime,
    dischtime,
    hospital_expire_flag,
    dod
  FROM diagnoses_with_age
),
-- Define Elixhauser comorbidities (simplified set using ICD-10 codes)
comorbidity_codes AS (
  SELECT 'I25.2' AS icd_code, 'chronic_heart_failure' AS condition UNION ALL
  SELECT 'I50.0', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.1', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.20', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.21', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.22', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.23', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.30', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.31', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.32', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.33', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.40', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.41', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.42', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.43', 'chronic_heart_failure' UNION ALL
  SELECT 'I50.9', 'chronic_heart_failure' UNION ALL
  SELECT 'I48.0', 'arrhythmia' UNION ALL
  SELECT 'I48.1', 'arrhythmia' UNION ALL
  SELECT 'I48.2', 'arrhythmia' UNION ALL
  SELECT 'I48.3', 'arrhythmia' UNION ALL
  SELECT 'I48.9', 'arrhythmia' UNION ALL
  SELECT 'I49.01', 'arrhythmia' UNION ALL
  SELECT 'I49.02', 'arrhythmia' UNION ALL
  SELECT 'I49.1', 'arrhythmia' UNION ALL
  SELECT 'I49.2', 'arrhythmia' UNION ALL
  SELECT 'I49.3', 'arrhythmia' UNION ALL
  SELECT 'I49.4', 'arrhythmia' UNION ALL
  SELECT 'I49.5', 'arrhythmia' UNION ALL
  SELECT 'I49.8', 'arrhythmia' UNION ALL
  SELECT 'I49.9', 'arrhythmia' UNION ALL
  SELECT 'I21.09', 'myocardial_infarction' UNION ALL
  SELECT 'I21.11', 'myocardial_infarction' UNION ALL
  SELECT 'I21.29', 'myocardial_infarction' UNION ALL
  SELECT 'I21.3', 'myocardial_infarction' UNION ALL
  SELECT 'I21.4', 'myocardial_infarction' UNION ALL
  SELECT 'I22.1', 'myocardial_infarction' UNION ALL
  SELECT 'I22.2', 'myocardial_infarction' UNION ALL
  SELECT 'I22.8', 'myocardial_infarction' UNION ALL
  SELECT 'I22.9', 'myocardial_infarction' UNION ALL
  SELECT 'I25.2', 'myocardial_infarction' UNION ALL
  SELECT 'I63.0', 'stroke' UNION ALL
  SELECT 'I63.1', 'stroke' UNION ALL
  SELECT 'I63.2', 'stroke' UNION ALL
  SELECT 'I63.3', 'stroke' UNION ALL
  SELECT 'I63.4', 'stroke' UNION ALL
  SELECT 'I63.5', 'stroke' UNION ALL
  SELECT 'I63.8', 'stroke' UNION ALL
  SELECT 'I63.9', 'stroke' UNION ALL
  SELECT 'G40.0', 'seizure' UNION ALL
  SELECT 'G40.1', 'seizure' UNION ALL
  SELECT 'G40.2', 'seizure' UNION ALL
  SELECT 'G40.3', 'seizure' UNION ALL
  SELECT 'G40.4', 'seizure' UNION ALL
  SELECT 'G40.5', 'seizure' UNION ALL
  SELECT 'G40.8', 'seizure' UNION ALL
  SELECT 'G40.9', 'seizure' UNION ALL
  SELECT 'G41.0', 'seizure' UNION ALL
  SELECT 'G41.1', 'seizure' UNION ALL
  SELECT 'G41.2', 'seizure' UNION ALL
  SELECT 'G41.8', 'seizure' UNION ALL
  SELECT 'G41.9', 'seizure'
),
-- Get all diagnoses for these patients
all_diagnoses AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    d.icd_code,
    di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.subject_id IN (SELECT subject_id FROM pe_patients)
),
-- Assign comorbidities to patients
patient_comorbidities;