WITH sepsis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE d.long_title LIKE '%sepsis%'
),

icu_patients AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    p.gender,
    p.anchor_age,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    CASE WHEN sa.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_sepsis
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  LEFT JOIN sepsis_admissions sa 
    ON i.hadm_id = sa.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),

procedure_counts AS (
  SELECT 
    p.stay_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN icu_patients i 
    ON p.stay_id = i.stay_id
  WHERE p.starttime BETWEEN i.intime AND i.intime + INTERVAL '24' HOUR
  GROUP BY p.stay_id
),

sepsis_procedures AS (
  SELECT pc.procedure_count
  FROM procedure_counts pc
  JOIN icu_patients i 
    ON pc.stay_id = i.stay_id
  WHERE i.has_sepsis = 1
),

sepsis_percentiles AS (
  SELECT 
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY procedure_count) AS sepsis_75th,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY procedure_count) AS sepsis_90th
  FROM sepsis_procedures
),

non_sepsis_stats AS (
  SELECT 
    AVG(los) AS non_sepsis_avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS non_sepsis_mortality
  FROM icu_patients
  WHERE has_sepsis = 0
),

sepsis_stats AS (
  SELECT 
    AVG(los) AS sepsis_avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS sepsis_mortality
  FROM icu_patients
  WHERE has_sepsis = 1
)

SELECT 
  sp.sepsis_75th,
  sp.sepsis_90th,
  ss.sepsis_avg_los,
  ss.sepsis_mortality,
  ns.non_sepsis_avg_los,
  ns.non_sepsis_mortality
FROM sepsis_percentiles sp
CROSS JOIN sepsis_stats ss
CROSS JOIN non_sepsis_stats ns;