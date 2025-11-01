WITH 
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 51 AND 61
),
admissions_ap AS (
  SELECT DISTINCT diag.hadm_id, 
         CASE WHEN diag.seq_num = (SELECT MIN(seq_num) FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 WHERE d2.hadm_id = diag.hadm_id) THEN 'Primary' ELSE 'Secondary' END AS diagnosis_priority
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  JOIN patients_filtered p ON diag.subject_id = p.subject_id
  WHERE d_diag.long_title LIKE '%Acute pancreatitis%' AND diag.icd_version = 10
),
admissions_los AS (
  SELECT a.hadm_id, a.diagnosis_priority,
         DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
  FROM admissions_ap a
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad ON a.hadm_id = ad.hadm_id
),
radiography_ct_counts AS (
  SELECT hadm_id, COUNT(*) AS ct_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%CT%' OR label LIKE '%Radiography%')
  GROUP BY hadm_id
)
SELECT 
  CASE 
    WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Outside range'
  END AS los_category,
  a.diagnosis_priority,
  COUNT(DISTINCT a.hadm_id) AS patient_count,
  AVG(r.ct_count) AS mean_radiography_ct
FROM admissions_los a
LEFT JOIN radiography_ct_counts r ON a.hadm_id = r.hadm_id
WHERE a.los_days BETWEEN 1 AND 7
GROUP BY los_category, a.diagnosis_priority
ORDER BY los_category, a.diagnosis_priority;