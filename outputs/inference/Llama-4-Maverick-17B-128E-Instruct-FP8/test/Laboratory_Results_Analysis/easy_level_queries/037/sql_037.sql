WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
sepsis_patients AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Sepsis%' OR d_diag.long_title LIKE '%septic%'
),
platelet_counts AS (
  SELECT le.hadm_id, MAX(le.valuenum) AS max_platelet
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_li
    ON le.itemid = d_li.itemid
  WHERE d_li.label LIKE '%Platelet Count%' AND le.valuenum IS NOT NULL
  GROUP BY le.hadm_id
)
SELECT APPROX_QUANTILES(max_platelet, 100)[OFFSET(75)] AS percentile_75th
FROM platelet_counts
WHERE hadm_id IN (
  SELECT hadm_id
  FROM sepsis_patients
  INNER JOIN male_patients
    ON sepsis_patients.subject_id = male_patients.subject_id
);