WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code IN ('E11', 'E11.9', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8') -- T2DM codes
), PatientHeartFailure AS (
  SELECT
    p.subject_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code IN ('I50', 'I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.8', 'I50.9') -- Heart Failure codes
), PatientCohort AS (
  SELECT
    pd.subject_id
  FROM
    PatientDiagnosis AS pd
  JOIN
    PatientHeartFailure AS phf
    ON pd.subject_id = phf.subject_id
  WHERE
    pd.gender = 'M' AND pd.anchor_age BETWEEN 36 AND 46
), MedicationInitiation AS (
  SELECT
    p.subject_id,
    p.starttime,
    p.drug,
    p.drug_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN
    PatientCohort AS pc
    ON p.subject_id = pc.subject_id
  WHERE
    p.starttime IS NOT NULL
), MedicationClass AS (
  SELECT
    mi.subject_id,
    mi.starttime,
    CASE
      WHEN mi.drug LIKE '%metformin%' THEN 'Metformin'
      WHEN mi.drug LIKE '%sulfonylurea%' THEN 'Sulfonylurea'
      WHEN mi.drug LIKE '%glitazone%' THEN 'Glitazone'
      WHEN mi.drug LIKE '%dpp4%' THEN 'DPP-4 inhibitor'
      WHEN mi.drug LIKE '%sglt2%' THEN 'SGLT2 inhibitor'
      WHEN mi.drug LIKE '%glp1%' THEN 'GLP-1 receptor agonist'
      WHEN mi.drug LIKE '%insulin%' THEN 'Insulin'
      ELSE 'Other'
    END AS drug_class
  FROM
    MedicationInitiation AS mi
), TimeWindows AS (
  SELECT
    mc.subject_id,
    mc.starttime,
    mc.drug_class,
    CASE
      WHEN mc.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 12 HOUR) THEN 'First 12h'
      WHEN mc.starttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AND a.dischtime THEN 'Final 48h'
      ELSE 'Other'
    END AS time_window
  FROM
    MedicationClass AS mc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON mc.subject_id = a.subject_id
), TimeWindowCounts AS (
  SELECT
    tw.time_window,
    tw.drug_class,
    COUNT(DISTINCT tw.subject_id) AS patient_count
  FROM
    TimeWindows AS tw
  WHERE
    tw.time_window IN ('First 12h', 'Final 48h')
  GROUP BY
    tw.time_window,
    tw.drug_class
), TotalPatients AS (
  SELECT
    COUNT(DISTINCT pc.subject_id) AS total_patients
  FROM
    PatientCohort AS pc;