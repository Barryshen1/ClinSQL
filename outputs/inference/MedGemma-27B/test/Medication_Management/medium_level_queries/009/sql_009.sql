WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
  ),
  Diagnosis AS (
    SELECT
      d.subject_id,
      d.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    WHERE
      d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
      AND d.icd_version = 10
    GROUP BY
      d.subject_id,
      d.hadm_id
  ),
  AcuteHF AS (
    SELECT
      d.subject_id,
      d.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    WHERE
      d.icd_code IN ('I50', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9') -- Acute HF codes
      AND d.icd_version = 10
    GROUP BY
      d.subject_id,
      d.hadm_id
  ),
  AdmissionInfo AS (
    SELECT
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    WHERE
      a.hadm_id IN (
        SELECT
          d.hadm_id
        FROM
          Diagnosis AS d
        INNER JOIN
          AcuteHF AS hf ON d.hadm_id = hf.hadm_id
      )
  ),
  MedicationEvents AS (
    SELECT
      e.subject_id,
      e.hadm_id,
      e.charttime,
      e.medication
    FROM
      `physionet-data.mimiciv_3_1_hosp.emar` AS e
    WHERE
      e.medication LIKE '%insulin%'
      OR e.medication LIKE '%metformin%'
      OR e.medication LIKE '%glipizide%'
      OR e.medication LIKE '%glyburide%'
      OR e.medication LIKE '%glimepiride%'
      OR e.medication LIKE '%pioglitazone%'
      OR e.medication LIKE '%rosiglitazone%'
      OR e.medication LIKE '%sitagliptin%'
      OR e.medication LIKE '%saxagliptin%'
      OR e.medication LIKE '%linagliptin%'
      OR e.medication LIKE '%alogliptin%'
      OR e.medication LIKE '%canagliflozin%'
      OR e.medication LIKE '%dapagliflozin%'
      OR e.medication LIKE '%empagliflozin%'
      OR e.medication LIKE '%acarbose%'
      OR e.medication LIKE '%repaglinide%'
      OR e.medication LIKE '%nateglinide%'
      OR e.medication LIKE '%chlorpropamide%'
      OR e.medication LIKE '%tolbutamide%'
      OR e.medication LIKE '%tolazamide%'
      OR e.medication LIKE '%glipizide%'
      OR e.medication LIKE '%glyburide%'
      OR e.medication LIKE '%glimepiride%'
      OR e.medication LIKE '%pioglitazone%'
      OR e.medication LIKE '%rosiglitazone%'
      OR e.medication LIKE '%sitagliptin%'
      OR e.medication LIKE '%saxagliptin%'
      OR e.medication LIKE '%linagliptin%'
      OR e.medication LIKE '%alogliptin%'
      OR e.medication LIKE '%canagliflozin%'
      OR e.medication LIKE '%dapagliflozin%'
      OR e.medication LIKE '%empagliflozin%'
      OR e.medication LIKE '%acarbose%'
      OR e.medication LIKE '%repaglinide%'
      OR e.medication LIKE '%;