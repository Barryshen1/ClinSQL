WITH 
first_icu_stay AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY ie.intime) AS icu_stay_num
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE 
    p.gender = 'M' AND p.anchor_age BETWEEN 88 AND 98
),
pneumonia_patients AS (
  SELECT DISTINCT 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    d.long_title LIKE '%Pneumonia%'
),
procedure_counts AS (
  SELECT 
    fis.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM 
    first_icu_stay fis
  JOIN 
    pneumonia_patients pp ON fis.hadm_id = pp.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON fis.stay_id = pe.stay_id
  WHERE 
    fis.icu_stay_num = 1 AND pe.starttime BETWEEN fis.intime AND TIMESTAMP_ADD(fis.intime, INTERVAL 72 HOUR)
  GROUP BY 
    fis.stay_id
),
quintiles AS (
  SELECT 
    stay_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM 
    procedure_counts
),
stats AS (
  SELECT 
    q.quintile,
    AVG(q.procedure_count) AS avg_procedure_count,
    AVG(TIMESTAMP_DIFF(fis.outtime, fis.intime, HOUR) / 24) AS avg_icu_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(fis.stay_id) * 100 AS in_hospital_mortality_pct
  FROM 
    quintiles q
  JOIN 
    first_icu_stay fis ON q.stay_id = fis.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON fis.hadm_id = a.hadm_id
  WHERE 
    fis.icu_stay_num = 1
  GROUP BY 
    q.quintile
)
SELECT 
  quintile,
  avg_procedure_count,
  avg_icu_los,
  in_hospital_mortality_pct
FROM 
  stats
ORDER BY 
  quintile;