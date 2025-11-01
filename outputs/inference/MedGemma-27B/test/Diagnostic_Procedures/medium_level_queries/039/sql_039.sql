WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 77 AND 87
    AND gender = 'M'
), AdmissionInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.discharge_location,
    a.admission_location,
    a.deathtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
), DiagnosisInfo AS (
  SELECT
    a.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%asthma%'
    AND d.seq_num = 1
), ICUStayInfo AS (
  SELECT
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.icustays` AS i
    ON a.hadm_id = i.hadm_id
), ProcedureInfo AS (
  SELECT
    a.hadm_id,
    p.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.hadm_id = p.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
    ON p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
  WHERE
    dp.long_title LIKE '%CT%' OR dp.long_title LIKE '%MRI%'
), ProcedureCounts AS (
  SELECT
    hadm_id,
    COUNT(icd_code) AS procedure_count
  FROM
    ProcedureInfo
  GROUP BY
    hadm_id
), AdmissionLength AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS admission_length
  FROM
    AdmissionInfo
)
SELECT
  CASE
    WHEN i.stay_id IS NOT NULL
    THEN 'ICU'
    ELSE 'Non-ICU'
  END AS icu_status,
  CASE
    WHEN al.admission_length BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN al.admission_length BETWEEN 5 AND 8
    THEN '5-8 days'
    ELSE 'Other'
  END AS admission_length_group,
  AVG(pc.procedure_count) AS mean_procedures,
  MIN(pc.procedure_count) AS min_procedures,
  MAX(pc.procedure_count) AS max_procedures
FROM
  AdmissionInfo AS a
INNER JOIN
  DiagnosisInfo AS di
  ON a.hadm_id = di.hadm_id
LEFT JOIN
  ICUStayInfo AS i
  ON a.hadm_id = i.had;