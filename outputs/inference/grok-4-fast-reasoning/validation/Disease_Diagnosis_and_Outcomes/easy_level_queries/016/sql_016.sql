WITH pneumonia_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%pneumonia%'
),
copd_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chronic obstructive pulmonary disease%'
),
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 68 AND 78
),
pneumonia_adms AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN pneumonia_codes pc ON di.icd_code = pc.icd_code AND di.icd_version = pc.icd_version
  INNER JOIN eligible_patients ep ON di.subject_id = ep.subject_id
),
copd_adms AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN copd_codes cc ON di.icd_code = cc.icd_code AND di.icd_version = cc.icd_version
  INNER JOIN eligible_patients ep ON di.subject_id = ep.subject_id
),
both_adms AS (
  SELECT pa.hadm_id
  FROM pneumonia_adms pa
  INNER JOIN copd_adms ca ON pa.hadm_id = ca.hadm_id
),
admissions AS (
  SELECT a.hadm_id, DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  INNER JOIN both_adms ba ON a.hadm_id = ba.hadm_id
  WHERE a.dischtime > a.admittime  -- Ensures valid LOS
)
SELECT
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los
FROM admissions
WHERE los > 0;