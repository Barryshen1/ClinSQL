WITH cohort AS (
  SELECT 
    a.hadm_id, 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND REGEXP_CONTAINS(dd.long_title, r'(?i)(hemorrhage|bleeding)')
    AND REGEXP_CONTAINS(dd.long_title, r'(?i)(upper|gastric|duodenal|jejunal|esophageal|peptic|stomach|hematemesis|mallory|dieulafoy|varices)')
    AND a.dischtime > a.admittime
)
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM 
  cohort;