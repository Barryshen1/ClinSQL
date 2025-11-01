SELECT
  AVG(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS avg_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd
  ON adm.hadm_id = dicd.hadm_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 78 AND 88
  AND dicd.seq_num = 1 -- Primary diagnosis
  AND (
    -- ICD-9 codes for Ischemic Heart Disease / Acute Coronary Syndrome
    (dicd.icd_version = 9 AND (
      dicd.icd_code LIKE '410%' OR -- Acute myocardial infarction
      dicd.icd_code LIKE '411%' OR -- Other acute and subacute forms of ischemic heart disease (includes unstable angina)
      dicd.icd_code LIKE '413%' OR -- Angina pectoris
      dicd.icd_code LIKE '414%'    -- Other forms of chronic ischemic heart disease
    ))
    OR
    -- ICD-10 codes for Ischemic Heart Disease / Acute Coronary Syndrome
    (dicd.icd_version = 10 AND (
      dicd.icd_code LIKE 'I20%' OR -- Angina pectoris
      dicd.icd_code LIKE 'I21%' OR -- Acute myocardial infarction
      dicd.icd_code LIKE 'I22%' OR -- Subsequent myocardial infarction
      dicd.icd_code LIKE 'I24%' OR -- Other acute ischemic heart diseases
      dicd.icd_code LIKE 'I25%'    -- Chronic ischemic heart disease
    ))
  );