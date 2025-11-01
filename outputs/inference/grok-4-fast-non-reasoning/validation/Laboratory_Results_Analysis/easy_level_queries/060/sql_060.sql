WITH pneumonia_admissions AS (
  SELECT DISTINCT 
    a.hadm_id,
    a.admittime,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND d.icd_code LIKE 'J18%'
    AND d.icd_version = '10'  -- Primarily ICD-10 in MIMIC-IV
    AND d.seq_num = 1  -- Primary diagnosis
),
glucose_labs AS (
  SELECT 
    l.hadm_id,
    l.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  INNER JOIN 
    pneumonia_admissions pa
    ON l.hadm_id = pa.hadm_id
  WHERE 
    LOWER(li.label) LIKE '%glucose%' 
    AND li.fluid = 'Blood'
    AND li.category = 'Chemistry'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
    AND l.valueuom IN ('mg/dL', '%')
    AND l.charttime >= pa.admittime
    AND EXTRACT(HOUR FROM (l.charttime - pa.admittime)) <= 24
)
SELECT 
  PERCENTILE_CONT(0.75, valuenum) OVER() AS p75_mean_glucose_first_24h
FROM (
  SELECT 
    hadm_id,
    AVG(valuenum) AS mean_glucose
  FROM 
    glucose_labs
  GROUP BY 
    hadm_id
  HAVING 
    mean_glucose IS NOT NULL
);