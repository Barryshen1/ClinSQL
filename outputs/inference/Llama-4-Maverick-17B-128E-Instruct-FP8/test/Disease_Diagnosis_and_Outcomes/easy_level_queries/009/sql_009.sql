WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 75 AND 85
  AND (diag.long_title LIKE '%Ischaemic heart disease%' OR diag.long_title LIKE '%Acute coronary syndrome%' OR diag.long_title LIKE '%Chronic obstructive pulmonary disease%')
),
los AS (
  SELECT a.subject_id, DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_cohort p ON a.subject_id = p.subject_id
  WHERE p.anchor_age = 80
)
SELECT APPROX_QUANTILES(hospital_los, 100)[OFFSET(75)] AS percentile_75th_los
FROM los;