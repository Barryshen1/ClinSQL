WITH copd_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d ON p.subject_id = d.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 90
    AND LOWER(d_icd.long_title) LIKE '%chronic obstructive pulmonary disease%'
),
creatinine_first_24h AS (
  SELECT 
    l.subject_id,
    a.admittime,
    l.charttime,
    l.valuenum AS creatinine_value
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl ON l.itemid = dl.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  INNER JOIN copd_patients cp ON l.subject_id = cp.subject_id
  WHERE LOWER(dl.label) LIKE '%creatinine%'
    AND l.valuenum IS NOT NULL
    AND l.charttime >= a.admittime
    AND l.charttime <= a.admittime + INTERVAL 24 HOUR
),
patient_avg_creatinine AS (
  SELECT 
    subject_id,
    AVG(creatinine_value) AS avg_creatinine_first_24h
  FROM creatinine_first_24h
  GROUP BY subject_id
  HAVING COUNT(creatinine_value) > 0
)
SELECT 
  STDDEV(avg_creatinine_first_24h) AS std_dev_avg_creatinine_first_24h
FROM patient_avg_creatinine;