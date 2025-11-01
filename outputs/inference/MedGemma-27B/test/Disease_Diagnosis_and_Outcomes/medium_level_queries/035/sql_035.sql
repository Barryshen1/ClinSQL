WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 74
    AND gender = 'F'
),
DiagnosisInfo AS (
  SELECT
    p.subject_id,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN PatientInfo AS p
    ON d.subject_id = p.subject_id
  WHERE
    d.seq_num = 1
    AND d.icd_code LIKE 'K92%' -- Upper GI bleed
    AND d.icd_version = '9'
),
UpperGIBleed AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.deathtime,
    h.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  INNER JOIN DiagnosisInfo AS d
    ON h.subject_id = d.subject_id
    AND h.hadm_id = d.hadm_id
),
LowerGIBleed AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.deathtime,
    h.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  INNER JOIN DiagnosisInfo AS d
    ON h.subject_id = d.subject_id
    AND h.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'K92%' -- Lower GI bleed
    AND d.icd_version = '9'
),
CombinedBleed AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    'Upper GI Bleed' AS bleed_type
  FROM
    UpperGIBleed
  UNION ALL
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    'Lower GI Bleed' AS bleed_type
  FROM
    LowerGIBleed
),
PatientAgeGroup AS (
  SELECT
    subject_id,
    hadm_id,
    bleed_type,
    CASE
      WHEN anchor_age BETWEEN 69 AND 79
      THEN '69-79'
      ELSE 'Other'
    END AS age_group
  FROM
    CombinedBleed
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON CombinedBleed.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 69 AND 79
),
ICUAdmission;