WITH PatientDiagnosis AS (
  -- Identify patients with both T2D and heart failure
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age = 43
    AND d.icd_code IN ('E11', 'E11.9', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.1') -- T2D codes
    AND d.icd_code IN ('I50', 'I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.7', 'I50.8', 'I50.0') -- Heart Failure codes
), PatientCohort AS (
  -- Filter patients to the target age range and diagnoses
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN PatientDiagnosis AS pd
    ON p.subject_id = pd.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 38 AND 48
), MedicationInitiation AS (
  -- Identify medication initiations within the first 72 hours
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    CASE
      WHEN LOWER(rx.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(rx.drug) LIKE '%metformin%' OR LOWER(rx.drug) LIKE '%glipizide%' OR LOWER(rx.drug) LIKE '%glyburide%' OR LOWER(rx.drug) LIKE '%glimepiride%' OR LOWER(rx.drug) LIKE '%pioglitazone%' OR LOWER(rx.drug) LIKE '%rosiglitazone%' OR LOWER(rx.drug) LIKE '%sitagliptin%' OR LOWER(rx.drug) LIKE '%saxagliptin%' OR LOWER(rx.drug) LIKE '%linagliptin%' OR LOWER(rx.drug) LIKE '%alogliptin%' OR LOWER(rx.drug) LIKE '%canagliflozin%' OR LOWER(rx.drug) LIKE '%dapagliflozin%' OR LOWER(rx.drug) LIKE '%empagliflozin%' THEN 'Oral Agent'
      ELSE 'Other'
    END AS medication_type,
    rx.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
    ON p.subject_id = rx.subject_id
  WHERE
    p.subject_id IN (SELECT subject_id FROM PatientCohort)
    AND rx.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 72 HOUR)
    AND rx.drug_type = 'medication'
), FinalMedicationInitiation AS (
  -- Identify medication initiations within the final 72 hours
  SELECT
    p.subject_id,
    p.hadm_id,
    p.dischtime,
    CASE
      WHEN LOWER(rx.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(rx.drug) LIKE '%metformin%' OR LOWER(rx.drug) LIKE '%glipizide%' OR LOWER(rx.drug) LIKE '%glyburide%' OR LOWER(rx.drug) LIKE '%glimepiride%' OR LOWER(rx.drug) LIKE '%pioglitazone%' OR LOWER(rx.drug) LIKE '%rosiglitazone%' OR LOWER(rx.drug) LIKE '%sitagliptin%' OR LOWER(rx.drug) LIKE '%saxagliptin%' OR LOWER(rx.drug) LIKE '%linagliptin%' OR LOWER(rx.drug) LIKE '%alogliptin%' OR LOWER(rx.drug) LIKE '%canagliflozin%' OR LOWER(rx.;