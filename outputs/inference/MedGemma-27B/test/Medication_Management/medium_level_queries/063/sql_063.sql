WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.admission_type = 'EMERGENCY' -- Assuming emergency admissions are relevant for this cohort
),
DiagnosisCohort AS (
  SELECT DISTINCT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON pc.subject_id = d.subject_id AND pc.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes (ICD-10)
    AND d.icd_version = '10'
),
HeartFailureCohort AS (
  SELECT DISTINCT
    dc.subject_id,
    dc.hadm_id,
    dc.admittime,
    dc.dischtime
  FROM DiagnosisCohort AS dc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS hf
    ON dc.subject_id = hf.subject_id AND dc.hadm_id = hf.hadm_id
  WHERE
    hf.icd_code IN ('I50', 'I11', 'I13', 'I10') -- Heart failure codes (ICD-10)
    AND hf.icd_version = '10'
),
MedicationInitiation AS (
  SELECT
    hc.subject_id,
    hc.hadm_id,
    hc.admittime,
    hc.dischtime,
    p.starttime,
    p.drug,
    p.route,
    p.drug_type
  FROM HeartFailureCohort AS hc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON hc.subject_id = p.subject_id AND hc.hadm_id = p.hadm_id
  WHERE
    p.starttime BETWEEN hc.admittime AND hc.dischtime
    AND p.drug_type = 'Drug'
    AND (
      p.drug LIKE '%insulin%'
      OR p.drug LIKE '%glipizide%'
      OR p.drug LIKE '%glyburide%'
      OR p.drug LIKE '%glimepiride%'
      OR p.drug LIKE '%metformin%'
      OR p.drug LIKE '%pioglitazone%'
      OR p.drug LIKE '%rosiglitazone%'
      OR p.drug LIKE '%sitagliptin%'
      OR p.drug LIKE '%saxagliptin%' -- Fixed the unclosed string literal here
      OR p.drug LIKE '%linagliptin%'
      OR p.drug LIKE '%alogliptin%'
      OR p.drug LIKE '%canagliflozin%'
      OR p.drug LIKE '%dapagliflozin%'
      OR p.drug LIKE '%empagliflozin%'
      OR p.drug LIKE '%semaglutide%'
      OR p.drug LIKE '%liraglutide%'
      OR p.drug LIKE '%dulaglutide%'
      OR p.drug LIKE '%exenatide%'
    )
),
TimeBasedInitiation AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 'First 12h'
      WHEN starttime BETWEEN TIMESTAMP_ADD(dischtime, INTERVAL -72 HOUR) AND dischtime THEN 'Final 72h'
      ELSE 'Other'
    END AS time_;