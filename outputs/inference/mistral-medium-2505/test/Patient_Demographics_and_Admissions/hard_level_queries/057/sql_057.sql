WITH
-- Define UTI ICD-10 codes
uti_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
  AND icd_code IN ('N39.0', 'N10', 'N30.00', 'N30.01', 'N30.10', 'N30.11', 'N30.20', 'N30.21', 'N30.80', 'N30.81', 'N30.90', 'N30.91')
),

-- Get qualifying patients (male, 60-70, Medicare, admitted via ED)
qualifying_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'EMERGENCY'
    AND a.hospital_expire_flag = 0  -- Exclude patients who died during admission
),

-- Get UTI principal diagnoses
uti_admissions AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.admittime,
    q.dischtime,
    q.hospital_expire_flag
  FROM qualifying_patients q
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON q.hadm_id = d.hadm_id
  JOIN uti_codes u
    ON d.icd_code = u.icd_code
  WHERE d.seq_num = 1  -- Principal diagnosis
),

-- Get first qualifying admission per patient (index admission)
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) as admission_rank
  FROM uti_admissions
),

-- Calculate readmissions
patient_readmissions AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.admittime,
    i.dischtime,
    TIMESTAMP_DIFF(i.dischtime, i.admittime, DAY) AS los,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = i.subject_id
        AND a2.hadm_id != i.hadm_id
        AND a2.admittime > i.dischtime
        AND TIMESTAMP_DIFF(a2.admittime, i.dischtime, DAY) <= 30
    ) AS readmitted
  FROM index_admissions i
  WHERE i.admission_rank = 1  -- Only first qualifying admission per patient
)

SELECT
  -- Readmission rate
  COALESCE(COUNT(DISTINCT CASE WHEN readmitted THEN subject_id END) * 100.0 /
    NULLIF(COUNT(DISTINCT subject_id), 0), 0) AS readmission_rate,

  -- Median LOS for readmitted vs non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted THEN los ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN NOT readmitted THEN los ELSE NULL END, 2)[OFFSET(1)] AS median_los_non_readmitted,

  -- Percent with LOS > 9 days
  COALESCE(COUNT(DISTINCT CASE WHEN readmitted AND los > 9 THEN subject_id END) * 100.0 /
    NULLIF(COUNT(DISTINCT CASE WHEN readmitted THEN subject_id END), 0), 0) AS percent_los_gt9_readmitted,
  COALESCE(COUNT(DISTINCT CASE WHEN NOT readmitted AND los > 9 THEN subject_id END) * 100.0 /
    NULLIF(COUNT(DISTINCT CASE WHEN NOT readmitted THEN subject_id END), 0), 0) AS percent_los_gt9_non_readmitted

FROM patient_readmissions;