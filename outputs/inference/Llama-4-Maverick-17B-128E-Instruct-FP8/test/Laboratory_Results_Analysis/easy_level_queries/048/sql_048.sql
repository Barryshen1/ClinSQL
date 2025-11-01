WITH copd_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Chronic obstructive pulmonary disease%' 
  OR diag.long_title LIKE '%COPD%'
),
female_patients AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
  AND a.hadm_id IN (SELECT hadm_id FROM copd_patients)
  AND p.anchor_age BETWEEN 55 AND 57  -- Added age filter for the patient
),
creatinine_measurements AS (
  SELECT l.hadm_id, l.valuenum, 
         TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) AS hours_since_admission
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
  ON l.itemid = dl.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON l.hadm_id = a.hadm_id
  WHERE dl.label = 'Creatinine' AND l.valuenum IS NOT NULL
  AND l.hadm_id IN (SELECT hadm_id FROM female_patients)
  AND TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) BETWEEN 0 AND 24
),
avg_creatinine AS (
  SELECT hadm_id, AVG(valuenum) AS avg_creatinine
  FROM creatinine_measurements
  GROUP BY hadm_id
)

SELECT APPROX_QUANTILES(avg_creatinine, 100)[OFFSET(75)] AS percentile_75th
FROM avg_creatinine;