WITH hf_admissions AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I50%'
)
SELECT 
  MAX(creatinine_max) AS max_serum_creatinine_first_24h
FROM (
  SELECT 
    ha.hadm_id,
    MAX(l.valuenum) AS creatinine_max
  FROM 
    hf_admissions ha
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON 
    ha.subject_id = l.subject_id 
    AND ha.hadm_id = l.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li
  ON 
    l.itemid = li.itemid
  WHERE 
    LOWER(li.label) LIKE '%creatinine%'
    AND l.charttime >= ha.admittime
    AND l.charttime <= ha.admittime + INTERVAL 24 HOUR
    AND l.valuenum IS NOT NULL
  GROUP BY 
    ha.hadm_id
) creatinine_per_admission;