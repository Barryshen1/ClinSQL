WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.long_title AS diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F' AND p.anchor_age = 74 AND d.long_title LIKE '%heart failure%'
),
AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientInfo AS pi
    ON a.subject_id = pi.subject_id
),
DiagnosticEvents AS (
  SELECT
    h.hadm_id,
    h.charttime,
    h.hcpcs_cd,
    h.short_description
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
  JOIN AdmissionInfo AS ai
    ON h.hadm_id = ai.hadm_id
  WHERE
    h.short_description IN ('Imaging', 'ECG/EEG/PFT')
),
StayDuration AS (
  SELECT
    hadm_id,
    -- Calculate the length of stay in days
    (TIMESTAMP_DIFF(dischtime, admittime, DAY) + 1) AS los_days
  FROM AdmissionInfo
),
DiagnosticCounts AS (
  SELECT
    ai.hadm_id,
    ai.admission_type,
    sd.los_days,
    COUNT(de.hcpcs_cd) AS diagnostic_count
  FROM AdmissionInfo AS ai
  JOIN StayDuration AS sd
    ON ai.hadm_id = sd.hadm_id
  JOIN DiagnosticEvents AS de
    ON ai.hadm_id = de.hadm_id
  GROUP BY
    ai.hadm_id,
    ai.admission_type,
    sd.los_days
)
SELECT
  admission_type,
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Other'
  END AS stay_duration_group,
  AVG(diagnostic_count) AS mean_diagnostics
FROM DiagnosticCounts
GROUP BY
  admission_type,
  stay_duration_group
ORDER BY
  admission_type,
  stay_duration_group;