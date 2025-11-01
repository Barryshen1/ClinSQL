WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55 -- Age range 45-55
    AND d.icd_code IN ('E11', 'E11.9', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8') -- Type 2 Diabetes codes
    AND d.icd_code IN ('I50', 'I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.7', 'I50.8') -- Heart Failure codes
    AND a.los >= 48
  GROUP BY
    p.subject_id
),
MedicationOrders AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    p.route
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON a.hadm_id = p.hadm_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
),
First48hMedications AS (
  SELECT
    subject_id,
    hadm_id,
    drug,
    route
  FROM MedicationOrders
  WHERE
    starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),
Final24hMedications AS (
  SELECT
    subject_id,
    hadm_id,
    drug,
    route
  FROM MedicationOrders
  WHERE
    starttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 24 HOUR) AND a.dischtime
),
InsulinMedications AS (
  SELECT
    subject_id,
    hadm_id
  FROM First48hMedications
  WHERE
    drug LIKE 'Insulin%'
  GROUP BY
    subject_id,
    hadm_id
),
OralAgentMedications AS (
  SELECT
    subject_id,
    hadm_id
  FROM First48hMedications
  WHERE
    drug NOT LIKE 'Insulin%'
    AND drug NOT LIKE 'Metformin%'
    AND drug NOT LIKE 'Sulfonylurea%'
    AND drug NOT LIKE 'Thiazolidinedione%'
    AND drug NOT LIKE 'DPP-4 inhibitor%'
    AND drug NOT LIKE 'SGLT2 inhibitor%'
    AND drug NOT LIKE 'GLP-;