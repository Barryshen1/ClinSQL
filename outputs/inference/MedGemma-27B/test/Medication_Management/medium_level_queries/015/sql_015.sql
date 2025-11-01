WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code = 'E11.9' -- Diabetes mellitus type 2 without complications
  ), PatientHF AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code LIKE 'I50%' -- Acute heart failure
  ), PatientInfo AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.admittime,
      a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M' AND p.anchor_age BETWEEN 42 AND 52
  ), MedicationEvents AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      e.charttime,
      e.medication
    FROM PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
      ON p.subject_id = e.subject_id AND a.hadm_id = e.hadm_id
  ), MedicationClasses AS (
    SELECT
      subject_id,
      gender,
      anchor_age,
      admittime,
      dischtime,
      charttime,
      medication,
      CASE
        WHEN LOWER(medication) LIKE '%insulin%' THEN 'Insulin'
        WHEN LOWER(medication) LIKE '%metformin%' THEN 'Metformin'
        WHEN LOWER(medication) LIKE '%sulfonylurea%' THEN 'Sulfonylurea'
        WHEN LOWER(medication) LIKE '%dpp-4%' THEN 'DPP-4'
        WHEN LOWER(medication) LIKE '%sglt2%' THEN 'SGLT2'
        WHEN LOWER(medication) LIKE '%glp-1%' THEN 'GLP-1'
        WHEN LOWER(medication) LIKE '%tzd%' THEN 'TZD'
        ELSE NULL
      END AS drug_class
    FROM MedicationEvents;