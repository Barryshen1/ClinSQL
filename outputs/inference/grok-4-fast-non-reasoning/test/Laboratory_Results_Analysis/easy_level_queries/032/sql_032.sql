WITH copd_admissions AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age >= 90
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'J44%'
),
first_24h_creatinine AS (
  SELECT 
    ca.hadm_id,
    AVG(le.valuenum) AS avg_creatinine
  FROM 
    copd_admissions ca
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ca.hadm_id = le.hadm_id
  WHERE 
    le.itemid = 50912
    AND le.valueuom = 'mg/dL'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= ca.admittime
    AND le.charttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 1 DAY)
  GROUP BY 
    ca.hadm_id
  HAVING 
    avg_creatinine IS NOT NULL
)
SELECT 
  STDDEV(avg_creatinine) AS stddev_serum_creatinine_first_24h
FROM 
  first_24h_creatinine;