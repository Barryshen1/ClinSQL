WITH PatientICU AS (
  -- Select relevant patient information and ICU stay details
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON a.hadm_id = ic.hadm_id
), DiagnosisProcedure AS (
  -- Select relevant diagnosis and procedure information
  SELECT
    dp.subject_id,
    dp.hadm_id,
    dp.stay_id,
    dp.charttime,
    dp.itemid,
    dp.value,
    dp.valueuom,
    dp.location,
    dp.locationcategory,
    dp.orderid,
    dp.linkorderid,
    dp.ordercategoryname,
    dp.ordercategorydescription,
    dp.patientweight,
    dp.isopenbag,
    dp.continueinnextdept,
    dp.statusdescription,
    dp.originalamount,
    dp.originalrate
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS dp
), Diagnosis AS (
  -- Select relevant diagnosis information
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
), ICDDiagnosis AS (
  -- Join diagnoses with ICD codes
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    icd.long_title
  FROM
    Diagnosis AS d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
    ON d.icd_code = icd.icd_code
    AND d.icd_version = icd.icd_version
), PulmonaryEmbolism AS (
  -- Identify patients with pulmonary embolism
  SELECT
    icd.subject_id,
    icd.hadm_id,
    icd.stay_id
  FROM
    ICDDiagnosis AS icd
  WHERE
    icd.icd_code = 'I26.9' -- Pulmonary embolism without acute cor pulmonale
    OR icd.icd_code = 'I26.0' -- Pulmonary embolism with acute cor pulmonale
    OR icd.icd_code = 'I26.1' -- Pulmonary embolism with acute right heart failure
    OR icd.icd_code = 'I26.2' -- Pulmonary embolism with acute right ventricular failure
), ProcedureCount AS (
  -- Count procedures within 72 hours of ICU admission
  SELECT
    pi.subject_id,
    pi.stay_id,
    COUNT(dp.itemid) AS procedure_count
  FROM
    PatientICU AS pi
  INNER JOIN
    DiagnosisProcedure AS dp
    ON pi.subject_id = dp.subject_id
    AND pi.stay_id = dp.stay_id
    AND dp.charttime BETWEEN pi.intime AND TIMESTAMP_ADD(pi.intime, INTERVAL 72 HOUR)
  GROUP BY
    pi.subject_id,
    pi.stay_id
), QuartileAnalysis AS (
  -- Stratify procedure counts into quartiles
  SELECT
    pc.subject_id,
    pc.stay_id,
    pc.procedure_count,
    NTILE(4) OVER (ORDER BY pc.procedure_count) AS procedure_quartile
  FROM
    ProcedureCount AS pc
), FinalAnalysis AS (
  -- Combine patient information, procedure quartiles, and mortality data
  SELECT;