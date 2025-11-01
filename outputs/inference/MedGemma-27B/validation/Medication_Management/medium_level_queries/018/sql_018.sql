WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    d.icd_code,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND d.icd_code IN ('E11', 'E11.9', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9') -- T2DM codes
    AND d.icd_code IN ('I50', 'I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.9') -- Heart Failure codes
    AND d.seq_num = 1 -- Primary diagnosis
),
MedicationUsage AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    rx.drug,
    rx.starttime,
    rx.stoptime,
    CASE
      WHEN rx.drug LIKE '%metformin%' THEN 'metformin'
      WHEN rx.drug LIKE '%sulfonylurea%' THEN 'sulfonylurea'
      WHEN rx.drug LIKE '%DPP4%' THEN 'dpp4'
      WHEN rx.drug LIKE '%SGLT2%' THEN 'sglt2'
      WHEN rx.drug LIKE '%TZD%' THEN 'tzd'
      ELSE 'other'
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
  INNER JOIN PatientCohort AS pc
    ON rx.subject_id = pc.subject_id AND rx.hadm_id = pc.hadm_id
  WHERE
    rx.drug LIKE '%metformin%'
    OR rx.drug LIKE '%sulfonylurea%'
    OR rx.drug LIKE '%DPP4%'
    OR rx.drug LIKE '%SGLT2%'
    OR rx.drug LIKE '%TZD%'
),
First72h AS (
  SELECT
    subject_id,
    hadm_id,
    drug_class,
    COUNT(DISTINCT pharmacy_id) AS medication_count
  FROM MedicationUsage
  WHERE
    starttime BETWEEN (
      SELECT
        a.admittime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      WHERE
        a.hadm_id = MedicationUsage.hadm_id
    ) + INTERVAL '72' HOUR AND (
      SELECT
        a.admittime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      WHERE
        a.hadm_id = MedicationUsage.hadm_id
    ) + INTERVAL '120' HOUR
  GROUP BY
    subject_id,
    hadm_id,
    drug_class
),
Final48h AS (
  SELECT
    subject_id,
    hadm_id,
    drug_class,
    COUNT(DISTINCT pharmacy_id) AS medication_count
  FROM MedicationUsage
  WHERE
    starttime BETWEEN (
      SELECT
        a.dischtime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      WHERE
        a.hadm_id = MedicationUsage.hadm_id
    ) - INTERVAL '48' HOUR AND (
      SELECT
        a.dischtime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      WHERE
        a.;