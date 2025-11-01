WITH pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Pneumonia%'  -- Adjust this condition based on specific pneumonia definitions
),
female_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
),
creatinine_measurements AS (
  SELECT l.hadm_id, AVG(l.valuenum) AS avg_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_l ON l.itemid = d_l.itemid
  INNER JOIN pneumonia_admissions pa ON l.hadm_id = pa.hadm_id
  WHERE d_l.label = 'Creatinine'  -- Ensure this matches the label for creatinine in d_labitems
  AND l.charttime BETWEEN pa.admittime AND TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR)
  GROUP BY l.hadm_id
),
female_pneumonia_admissions AS (
  SELECT pa.hadm_id
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON pa.hadm_id = adm.hadm_id
  INNER JOIN female_patients p ON adm.subject_id = p.subject_id
)

SELECT MIN(cm.avg_creatinine) AS min_avg_creatinine
FROM creatinine_measurements cm
WHERE cm.hadm_id IN (SELECT hadm_id FROM female_pneumonia_admissions);