WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 59 AND 69
),
ischemic_stroke_admissions AS (
  SELECT DISTINCT ad.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Ischemic stroke%' AND diag.seq_num = 1  
    AND ad.subject_id IN (SELECT subject_id FROM patient_filter)
),
hospital_los AS (
  SELECT ad.hadm_id, DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  WHERE ad.hadm_id IN (SELECT hadm_id FROM ischemic_stroke_admissions)
)
SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM hospital_los;