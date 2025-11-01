WITH sepsis_admissions AS (
  SELECT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON diag.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (d_diag.long_title LIKE '%sepsis%' OR d_diag.long_title LIKE '%septicemia%')
),
platelet_events AS (
  SELECT le.subject_id, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
    ON le.itemid = d_lab.itemid
  WHERE d_lab.label LIKE '%platelet%'
    AND le.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
    AND le.valuenum IS NOT NULL
),
max_platelet AS (
  SELECT subject_id, MAX(valuenum) AS peak_platelet
  FROM platelet_events
  GROUP BY subject_id
)
SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY peak_platelet) AS percentile_75
FROM max_platelet;