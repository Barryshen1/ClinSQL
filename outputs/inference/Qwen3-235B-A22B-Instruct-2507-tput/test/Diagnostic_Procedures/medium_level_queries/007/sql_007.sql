WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- Compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit,
    a.admittime,
    a.dischtime,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    di.seq_num,
    -- Flag if this admission has ACS
    di.icd_code,
    di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 50 AND 60
    AND (LOWER(d.long_title) LIKE '%myocardial infarction%'
       OR LOWER(d.long_title) LIKE '%unstable angina%'
       OR LOWER(d.long_title) LIKE '%acute coronary syndrome%')
),
acs_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    -- Classify diagnosis priority: primary if any ACS is primary (seq_num=1), else secondary
    CASE WHEN MIN(seq_num) = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM patient_admissions
  GROUP BY subject_id, hadm_id, los_days
  HAVING los_days BETWEEN 1 AND 8  -- Only keep 1–8 day stays
),
procedure_counts AS (
  SELECT
    a.hadm_id,
    a.los_days,
    a.diagnosis_type,
    COUNT(p.icd_code) AS num_procedures  -- Count procedures per admission using valid column
  FROM acs_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd p
    ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id, a.los_days, a.diagnosis_type
),
stratified AS (
  SELECT
    diagnosis_type,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    num_procedures
  FROM procedure_counts
  WHERE los_days BETWEEN 1 AND 8
)
SELECT
  diagnosis_type,
  los_group,
  APPROX_QUANTILES(num_procedures, 1000)[OFFSET(250)] AS p25_procedures,
  APPROX_QUANTILES(num_procedures, 1000)[OFFSET(500)] AS p50_procedures,
  APPROX_QUANTILES(num_procedures, 1000)[OFFSET(750)] AS p75_procedures
FROM stratified
WHERE los_group IS NOT NULL
GROUP BY diagnosis_type, los_group
ORDER BY diagnosis_type, los_group;