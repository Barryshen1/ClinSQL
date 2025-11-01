WITH PatientICUStay AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND ic.stay_id = 1 -- First ICU stay
), DiagnosisProcedure AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.intime,
    p.outtime,
    p.los,
    di.icd_code,
    di.icd_version,
    di.seq_num,
    pi.icd_code AS proc_icd_code,
    pi.icd_version AS proc_icd_version,
    pi.seq_num AS proc_seq_num
  FROM PatientICUStay AS p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id AND p.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    ON p.subject_id = pi.subject_id AND p.hadm_id = pi.hadm_id
), HepaticFailure AS (
  SELECT
    subject_id,
    hadm_id
  FROM DiagnosisProcedure
  WHERE
    icd_code IN ('571.2', '571.5', '571.8', '571.9', 'K71.1', 'K71.2', 'K71.3', 'K71.4', 'K71.5', 'K71.8', 'K71.9', 'K72.0', 'K72.1', 'K72.2', 'K72.3', 'K72.8', 'K72.9', 'K73.0', 'K73.1', 'K73.8', 'K73.9', 'K74.0', 'K74.1', 'K74.2', 'K74.3', 'K74.4', 'K74.5', 'K74.6', 'K74.8', 'K74.9', 'K75.0', 'K75.1', 'K75.2', 'K75.3', 'K75.8', 'K75.9', 'K76.0', 'K76.1', 'K76.2', 'K76.3', 'K76.4', 'K76.5', 'K76.6', 'K76.7', 'K76.8', 'K76.9') -- Added missing closing parenthesis
), ProcedureCount AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(proc_icd_code) AS procedure_count
  FROM DiagnosisProcedure
  WHERE
    hadm_id IN (SELECT hadm_id FROM HepaticFailure)
    AND proc_icd_code IS NOT NULL
  GROUP BY
    subject_id,
    hadm_id
), ProcedureQuartiles AS (
  SELECT
    subject_id,
    hadm_id,
    procedure_count,
    NTILE(4) OVER (ORDER BY procedure_count) AS procedure_quartile
  FROM ProcedureCount
), PatientInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.intime,
    p.outtime,
    p.los,
    a.hospital_expire_flag
  FROM PatientICUStay AS p
  JOIN `physionet-data.mimiciv_3_1_hosp;