WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age >= 75
    AND p.anchor_age < 85
), DiagnosisCohort AS (
  SELECT DISTINCT
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    a.hadm_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
    AND icd.long_title LIKE '%diabetes%'
), HeartFailureCohort AS (
  SELECT DISTINCT
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    a.hadm_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
    AND icd.long_title LIKE '%heart failure%'
), AdmissionLengthCohort AS (
  SELECT DISTINCT
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.hadm_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 36
), FinalCohort AS (
  SELECT DISTINCT
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
    AND a.subject_id IN (
      SELECT
        subject_id
      FROM DiagnosisCohort
    )
    AND a.subject_id IN (
      SELECT
        subject_id
      FROM HeartFailureCohort
    )
    AND a.subject_id IN (
      SELECT
        subject_id
      FROM AdmissionLengthCohort
    )
), GLP1Medications AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.starttime,
    p.drug
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM FinalCohort
    )
    AND p.drug LIKE '%semaglutide%'
    OR p.drug LIKE '%dulaglutide%'
    OR p.drug LIKE '%liraglutide%'
    OR p.drug LIKE '%exenatide%'
    OR p.drug LIKE '%lixisenatide%'
), GLP1Timing AS (
  SELECT
    subject_id,
    hadm_id,;