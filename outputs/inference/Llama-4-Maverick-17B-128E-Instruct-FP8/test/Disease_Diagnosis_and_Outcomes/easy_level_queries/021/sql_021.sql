WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),
diagnoses AS (
  SELECT 
    hadm_id,
    icd_code,
    icd_version
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),
hemorrhagic_stroke AS (
  SELECT 
    hadm_id
  FROM 
    diagnoses
  WHERE 
    (icd_version = 9 AND icd_code BETWEEN '430' AND '432')
    OR (icd_version = 10 AND icd_code BETWEEN 'I60' AND 'I62')
),
copd_exacerbation AS (
  SELECT 
    hadm_id
  FROM 
    diagnoses
  WHERE 
    (icd_version = 9 AND icd_code = '49121')
    OR (icd_version = 10 AND icd_code = 'J44.1')
),
eligible_patients AS (
  SELECT 
    pi.hadm_id,
    pi.los_days
  FROM 
    patient_info pi
  INNER JOIN 
    hemorrhagic_stroke hs ON pi.hadm_id = hs.hadm_id
  INNER JOIN 
    copd_exacerbation ce ON pi.hadm_id = ce.hadm_id
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_iqr_lower,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_iqr_upper
FROM 
  eligible_patients;