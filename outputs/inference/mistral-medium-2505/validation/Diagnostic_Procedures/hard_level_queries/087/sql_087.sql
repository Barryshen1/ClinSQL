WITH
-- Get female patients aged 56-66
female_patients AS (
  SELECT
    subject_id,
    anchor_age,
    anchor_year,
    gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 56 AND 66
),

-- Get ICH patients (ICD-9 and ICD-10 codes)
ich_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    female_patients p ON d.subject_id = p.subject_id
  WHERE
    -- ICD-10 codes for ICH
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'I61%' OR
      d.icd_code LIKE 'I62%'
    ))
    -- ICD-9 codes for ICH
    OR (d.icd_version = 9 AND (
      d.icd_code LIKE '431%' OR
      d.icd_code LIKE '432%'
    ))
),

-- Get first ICU stay for each admission
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    ich_patients ip ON i.subject_id = ip.subject_id AND i.hadm_id = ip.hadm_id
  WHERE
    i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
),
filtered_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM
    first_icu_stays
  WHERE
    stay_rank = 1
),

-- Calculate diagnostic intensity (lab tests, imaging, procedures) in first 72 hours
diagnostic_intensity AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los,
    -- Count distinct lab tests
    COUNT(DISTINCT l.itemid) AS lab_test_count,
    -- Count distinct imaging studies (radiology HCPCS codes)
    COUNT(DISTINCT CASE WHEN d.category = 'Radiology' THEN h.hcpcs_cd END) AS imaging_count,
    -- Count distinct procedures
    COUNT(DISTINCT p.icd_code) AS procedure_count,
    -- Total diagnostic intensity
    COUNT(DISTINCT l.itemid) +
    COUNT(DISTINCT CASE WHEN d.category = 'Radiology' THEN h.hcpcs_cd END) +
    COUNT(DISTINCT p.icd_code) AS total_diagnostic_intensity
  FROM
    filtered_icu_stays f
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON f.subject_id = l.subject_id
    AND f.hadm_id = l.hadm_id
    AND l.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON f.subject_id = h.subject_id
    AND f.hadm_id = h.hadm_id
    AND h.chartdate BETWEEN DATE(f.intime) AND DATE(TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR))
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON f.subject_id = p.subject_id
    AND f.hadm_id = p.hadm_id
    AND p.chartdate BETWEEN DATE(f.intime) AND DATE(TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR))
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = CAST(d.code AS STRING)
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id, f.intime, f.outtime, f.los
),

-- Get 95th percentile of diagnostic intensity
diagnostic_percentile AS (
  SELECT
    PERCENTILE_CONT(total_diagnostic_intensity, 0.95) OVER() AS p95_diagnostic_intensity
  FROM
    diagnostic_intensity
  LIMIT 1
),

-- Get mortality and LOS for ICH patients
ich_outcomes AS (
  SELECT
    COUNT(*) AS ich_patient_count,
    AVG(d.los) AS avg_ich_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS ich_mortality_count
  FROM
    filtered_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
),

-- Get general ICU population for comparison
general_icu_population AS (
  SELECT
    COUNT(*) AS general_patient_count,
    AVG(i.los) AS avg_general_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS general_mortality_count
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
)

-- Final results
SELECT
  dp.p95_diagnostic_intensity,
  io.ich_patient_count,
  io.avg_ich_los,
  io.ich_mortality_count,
  io.ich_mortality_count / io.ich_patient_count AS ich_mortality_rate,
  gip.general_patient_count,
  gip.avg_general_los,
  gip.general_mortality_count,
  gip.general_mortality_count / gip.general_patient_count AS general_mortality_rate
FROM
  diagnostic_percentile dp,
  ich_outcomes io,
  general_icu_population gip;