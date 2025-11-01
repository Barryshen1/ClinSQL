WITH dka_admissions AS (
  SELECT DISTINCT h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON h.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON h.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE icd.long_title LIKE '%ketoacidosis%' AND p.gender = 'F'
),
glucose_measurements AS (
  SELECT l.hadm_id, MAX(l.valuenum) AS peak_glucose
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label = 'Glucose'
  GROUP BY l.hadm_id
),
relevant_admissions AS (
  SELECT da.hadm_id
  FROM dka_admissions da
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON da.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 55 AND 61
),
peak_glucose AS (
  SELECT gm.peak_glucose AS peak_glucose_value
  FROM glucose_measurements gm
  INNER JOIN relevant_admissions ra ON gm.hadm_id = ra.hadm_id
)
SELECT APPROX_QUANTILES(peak_glucose_value, 100)[OFFSET(50)] AS median_peak_glucose
FROM peak_glucose;