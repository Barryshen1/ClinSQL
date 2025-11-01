WITH pneumonia_icd_codes AS (
  -- ICD-10: J12-J18, ICD-9: 480-486
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J1[2-8]'))
    OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^48[0-6]'))
),
first_admissions AS (
  -- Get first admission for each patient
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN (
    SELECT subject_id, MIN(admittime) AS first_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
  ) fa
    ON p.subject_id = fa.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.subject_id = p.subject_id AND a.admittime = fa.first_admittime
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),
pneumonia_first_admissions AS (
  -- Keep only first admissions with pneumonia diagnosis
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.subject_id = d.subject_id AND fa.hadm_id = d.hadm_id
  JOIN pneumonia_icd_codes picd
    ON d.icd_code = picd.icd_code AND d.icd_version = picd.icd_version
)
SELECT
  COUNTIF(hospital_expire_flag = 1) AS num_died,
  COUNT(*) AS num_total,
  SAFE_DIVIDE(COUNTIF(hospital_expire_flag = 1), COUNT(*)) * 100 AS in_hospital_mortality_percent
FROM pneumonia_first_admissions;