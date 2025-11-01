WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 46 -- Assuming the patient ID is 46, replace with the actual patient ID if known
),
AgeGroup AS (
  SELECT
    subject_id
  FROM
    PatientInfo
  WHERE
    gender = 'M' AND anchor_age BETWEEN 41 AND 51
),
Procedures AS (
  SELECT
    p.subject_id,
    pr.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON pr.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
  WHERE
    p.subject_id IN (SELECT subject_id FROM AgeGroup)
    AND pr.icd_code LIKE '930%' -- ICD-9 codes for ECG/Telemetry procedures
)
SELECT
  PERCENTILE_CONT(0.75, procedure_count) AS percentile_75
FROM (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS procedure_count
  FROM
    Procedures
  GROUP BY
    subject_id
);