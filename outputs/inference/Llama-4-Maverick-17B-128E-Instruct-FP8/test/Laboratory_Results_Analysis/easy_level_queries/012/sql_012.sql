WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age = 87 
    AND dicd.long_title LIKE '%Hemorrhagic stroke%'
),
platelet_measurements AS (
  SELECT 
    l.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  INNER JOIN 
    patient_admissions pa ON l.hadm_id = pa.hadm_id
  WHERE 
    dl.label = 'Platelet Count'
    AND DATE(l.charttime) = DATE(pa.dischtime)
)
SELECT 
  PERCENTILE_CONT(valuenum, 0.75) OVER () AS platelet_count_75th_percentile
FROM 
  platelet_measurements
LIMIT 1;