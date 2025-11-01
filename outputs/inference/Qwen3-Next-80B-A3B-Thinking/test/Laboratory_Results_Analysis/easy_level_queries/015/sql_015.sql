WITH pneumonia_patients AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND di.long_title LIKE '%pneumonia%'
),
creatinine_measurements AS (
  SELECT 
    p.hadm_id,
    l.valuenum
  FROM pneumonia_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON p.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
    ON l.itemid = di.itemid
  WHERE di.label LIKE '%creatinine%'
    AND di.fluid = 'Serum'
    AND l.charttime BETWEEN p.admittime AND p.admittime + INTERVAL '24' HOUR
    AND l.valuenum IS NOT NULL
),
avg_creatinine AS (
  SELECT 
    hadm_id,
    AVG(valuenum) AS avg_creat
  FROM creatinine_measurements
  GROUP BY hadm_id
)
SELECT MIN(avg_creat) AS min_24hr_avg_creatinine
FROM avg_creatinine;