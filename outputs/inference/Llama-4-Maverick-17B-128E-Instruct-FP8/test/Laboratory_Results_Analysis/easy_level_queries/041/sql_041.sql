WITH pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Pneumonia%'
),
patient_info AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 45 AND 55
  AND a.hadm_id IN (SELECT hadm_id FROM pneumonia_admissions)
),
creatinine_measurements AS (
  SELECT pi.hadm_id, AVG(l.valuenum) AS avg_creatinine
  FROM patient_info pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON pi.hadm_id = l.hadm_id
  WHERE l.itemid = 50912
  AND TIMESTAMP_DIFF(l.charttime, pi.admittime, HOUR) <= 24
  AND l.valuenum IS NOT NULL
  GROUP BY pi.hadm_id
)
SELECT STDDEV(avg_creatinine) AS sd_avg_creatinine
FROM creatinine_measurements;