WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
),
DiagnosisCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM PatientCohort AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
    AND d.icd_version = 9
),
HeartFailureCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM DiagnosisCohort AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code IN ('428', '4280', '4281', '4282', '4283', '4284', '4289', '3985') -- Heart failure codes
    AND d.icd_version = 9
  ),
FinalCohort AS (
  SELECT DISTINCT
    hf.subject_id
  FROM HeartFailureCohort AS hf
),
MedicationEvents AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.charttime,
    m.medication,
    m.drug_type
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS m
  WHERE
    m.subject_id IN (SELECT subject_id FROM FinalCohort)
),
MedicationTiming AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    medication,
    drug_type,
    CASE
      WHEN charttime BETWEEN (
        SELECT MIN(a.admittime)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE a.subject_id = MedicationEvents.subject_id
        AND a.hadm_id = MedicationEvents.hadm_id
      ) AND (
        SELECT MIN(a.admittime)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE a.subject_id = MedicationEvents.subject_id
        AND a.hadm_id = MedicationEvents.hadm_id
      ) + INTERVAL '48' HOUR
      THEN 'First 48h'
      WHEN charttime BETWEEN (
        SELECT MIN(a.admittime)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE a.subject_id = MedicationEvents.subject_id
        AND a.hadm_id = MedicationEvents.hadm_id
      ) + INTERVAL '48' HOUR AND (
        SELECT MIN(a.admittime)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE a.;