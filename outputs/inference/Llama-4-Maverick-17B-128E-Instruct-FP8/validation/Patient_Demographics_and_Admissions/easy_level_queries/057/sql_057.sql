WITH stroke_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 46 AND 56
  AND ((diag.icd_version = 9 AND (diag.icd_code LIKE '434%' OR diag.icd_code LIKE '436%'))
       OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I6%'))
),
first_admissions AS (
  SELECT subject_id, MIN(admittime) AS admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE subject_id IN (SELECT subject_id FROM stroke_patients)
  GROUP BY subject_id
),
first_hadm_ids AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN first_admissions fa ON a.subject_id = fa.subject_id AND a.admittime = fa.admittime
),
icu_los AS (
  SELECT fhi.subject_id, icu.los
  FROM first_hadm_ids fhi
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON fhi.hadm_id = icu.hadm_id
  WHERE icu.intime = (SELECT MIN(intime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE hadm_id = fhi.hadm_id)
)
SELECT 
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS Q3
FROM icu_los;