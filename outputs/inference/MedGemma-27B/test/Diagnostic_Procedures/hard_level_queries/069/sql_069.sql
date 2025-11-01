WITH PatientInfo AS (
  -- Select subject_id, gender, age, and admission time for relevant patients
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 44 AND 54
), DiagnosisInfo AS (
  -- Select subject_id and hadm_id for patients diagnosed with pulmonary embolism
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%pulmonary embolism%'
    AND d.seq_num = 1 -- Assuming the first diagnosis is the primary one
), ICUStayInfo AS (
  -- Select subject_id, hadm_id, and ICU stay information
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN
    DiagnosisInfo AS di
    ON i.subject_id = di.subject_id AND i.hadm_id = di.hadm_id
), ProcedureInfo AS (
  -- Select distinct procedures performed within the first 72 hours of ICU stay
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS p
  INNER JOIN
    ICUStayInfo AS i
    ON p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id AND p.stay_id = i.stay_id
  WHERE
    p.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
), ProcedureCount AS (
  -- Count the number of distinct procedures for each patient
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(DISTINCT itemid) AS procedure_count
  FROM
    ProcedureInfo
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
), QuintileInfo AS (
  -- Assign patients to quintiles based on procedure count
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count ASC) AS quintile
  FROM
    ProcedureCount
), FinalInfo AS (
  -- Combine patient information, ICU;