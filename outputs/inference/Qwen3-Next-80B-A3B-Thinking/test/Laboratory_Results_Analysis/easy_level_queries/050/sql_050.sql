WITH male_sepsis_admissions AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    p.gender = 'M'
    AND di.long_title LIKE '%sepsis%'
),
platelet_counts AS (
  SELECT 
    l.hadm_id, 
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN male_sepsis_admissions msa 
    ON l.hadm_id = msa.hadm_id
  WHERE 
    l.itemid = 51265
    AND l.charttime BETWEEN msa.admittime AND msa.dischtime
    AND l.valuenum IS NOT NULL
)
SELECT 
  STDDEV_POP(valuenum) AS std_dev_platelet
FROM platelet_counts
WHERE rn = 1;