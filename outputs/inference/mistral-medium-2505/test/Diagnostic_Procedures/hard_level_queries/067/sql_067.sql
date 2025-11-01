WITH
-- Define heart failure ICD codes (ICD-9 and ICD-10)
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '428.%')
     OR (icd_version = 10 AND icd_code LIKE 'I50.%')
),

-- Get male patients 70-80 with heart failure
hf_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN heart_failure_codes hf ON d.icd_code = hf.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
),

-- Get first ICU stay for each admission
first_icu_stays AS (
  SELECT *
  FROM (
    SELECT
      s.subject_id,
      s.hadm_id,
      s.stay_id,
      s.intime,
      s.outtime,
      s.los,
      ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.intime) AS stay_seq
    FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  )
  WHERE stay_seq = 1
),

-- Get diagnostic events in first 72 hours of ICU stay
diagnostic_events AS (
  SELECT
    f.subject_id,
    f.stay_id,
    COUNT(DISTINCT l.labevent_id) AS lab_tests,
    COUNT(DISTINCT m.microevent_id) AS micro_tests,
    COUNT(DISTINCT CASE WHEN h.short_description LIKE '%imaging%' THEN h.seq_num END) AS imaging_procedures
  FROM first_icu_stays f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON f.subject_id = l.subject_id
    AND f.hadm_id = l.hadm_id
    AND l.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
    ON f.subject_id = m.subject_id
    AND f.hadm_id = m.hadm_id
    AND m.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON f.subject_id = h.subject_id
    AND f.hadm_id = h.hadm_id
    AND h.chartdate BETWEEN DATE(f.intime) AND DATE(DATETIME_ADD(f.intime, INTERVAL 72 HOUR))
    AND h.short_description LIKE '%imaging%'
  GROUP BY f.subject_id, f.stay_id
),

-- Combine diagnostic counts
diagnostic_intensity AS (
  SELECT
    d.subject_id,
    d.stay_id,
    COALESCE(d.lab_tests, 0) + COALESCE(d.micro_tests, 0) + COALESCE(d.imaging_procedures, 0) AS total_diagnostics,
    f.los AS icu_los,
    a.hospital_expire_flag
  FROM diagnostic_events d
  JOIN first_icu_stays f ON d.subject_id = f.subject_id AND d.stay_id = f.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
),

-- Heart failure patient diagnostics
hf_diagnostics AS (
  SELECT
    'Heart Failure Patients (Male 70-80)' AS cohort,
    total_diagnostics,
    icu_los,
    hospital_expire_flag
  FROM diagnostic_intensity d
  JOIN hf_patients h ON d.subject_id = h.subject_id
),

-- General ICU population diagnostics
general_diagnostics AS (
  SELECT
    'General ICU Population' AS cohort,
    total_diagnostics,
    icu_los,
    hospital_expire_flag
  FROM diagnostic_intensity
)

-- Final results
SELECT
  cohort,
  COUNT(*) AS patient_count,
  AVG(total_diagnostics) AS mean_diagnostics,
  PERCENTILE_CONT(total_diagnostics, 0.5) AS median_diagnostics,
  PERCENTILE_CONT(total_diagnostics, 0.75) AS p75_diagnostics,
  PERCENTILE_CONT(total_diagnostics, 0.95) AS p95_diagnostics,
  AVG(icu_los) AS mean_icu_los,
  SUM(hospital_expire_flag) / COUNT(*) AS hospital_mortality
FROM (
  SELECT * FROM hf_diagnostics
  UNION ALL
  SELECT * FROM general_diagnostics
)
GROUP BY cohort;