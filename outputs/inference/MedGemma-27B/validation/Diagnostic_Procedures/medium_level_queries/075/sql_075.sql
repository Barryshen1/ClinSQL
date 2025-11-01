WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 64
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 59 AND 69
), DiagnosisInfo AS (
  SELECT
    a.hadm_id,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%ACS%'
), ProcedureInfo AS (
  SELECT
    p.hadm_id,
    p.icd_code,
    p.icd_version,
    dp.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
), ProcedureCounts AS (
  SELECT
    ai.hadm_id,
    ai.admittime,
    ai.dischtime,
    ai.gender,
    ai.anchor_age,
    COUNT(pi.icd_code) AS procedure_count,
    CASE
      WHEN di.seq_num = 1
      THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_priority
  FROM
    AdmissionInfo AS ai
  LEFT JOIN
    DiagnosisInfo AS di
    ON ai.hadm_id = di.hadm_id
  LEFT JOIN
    ProcedureInfo AS pi
    ON ai.hadm_id = pi.hadm_id
  GROUP BY
    ai.hadm_id,
    ai.admittime,
    ai.dischtime,
    ai.gender,
    ai.anchor_age,
    di.seq_num
), LengthOfStay AS (
  SELECT
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM
    AdmissionInfo
), FinalAnalysis AS (
  SELECT
    pc.hadm_id,
    pc.procedure_count,
    pc.diagnosis_priority,
    los.los,
    CASE
      WHEN los.los BETWEEN 1 AND 3
      THEN '1-3 days'
      WHEN los.los BETWEEN 4 AND 7
      THEN '4-7 days'
      ELSE 'Other'
    END AS los_category
  FROM
    ProcedureCounts AS pc
  JOIN
    LengthOfStay AS los
    ON pc.hadm_id = los.hadm_id
)
SELECT
  diagnosis_priority,
  los_category,
  APPROX_QUANTILES(procedure_count, [0.25, 0.5, 0.75]) AS (p25, p50, p75)
FROM
  FinalAnalysis
WHERE
  diagnosis_priority = ';