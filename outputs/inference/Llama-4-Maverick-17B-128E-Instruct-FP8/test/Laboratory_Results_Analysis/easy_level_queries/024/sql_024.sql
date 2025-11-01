WITH sepsis_admissions AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id, ad.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ad.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON ad.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND d_diag.long_title LIKE '%Sepsis%'
),
admission_platelet AS (
  SELECT sa.hadm_id, le.valuenum
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON sa.hadm_id = le.hadm_id
  WHERE le.itemid = 51265
  AND TIMESTAMP_DIFF(le.charttime, sa.admittime, HOUR) BETWEEN -24 AND 24
)
SELECT STDDEV(valuenum) AS sd_platelet_count
FROM admission_platelet;