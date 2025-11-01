WITH female_pneumonia_adms AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE 
    p.gender = 'F'
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 24
)
SELECT 
  MIN(avg_creat) AS min_24h_avg_serum_creatinine
FROM (
  SELECT 
    fpa.hadm_id,
    AVG(l.valuenum) AS avg_creat
  FROM 
    female_pneumonia_adms fpa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON fpa.subject_id = l.subject_id 
    AND fpa.hadm_id = l.hadm_id
  WHERE 
    l.itemid = 50912
    AND l.valuenum IS NOT NULL
    AND l.charttime >= fpa.admittime
    AND l.charttime < TIMESTAMP_ADD(fpa.admittime, INTERVAL 24 HOUR)
  GROUP BY 
    fpa.hadm_id
);