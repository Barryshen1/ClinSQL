WITH patient_data AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
    a.hadm_id,
    a.hospital_expire_flag,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 76 AND 86
),
ami_patients AS (
  SELECT DISTINCT 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE 
    LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
),
procedures AS (
  SELECT 
    pe.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN 
    patient_data pd ON pe.stay_id = pd.stay_id
  WHERE 
    pe.starttime <= pd.intime + INTERVAL 1 DAY
  GROUP BY 
    pe.stay_id
),
combined_data AS (
  SELECT 
    pd.subject_id,
    pd.hadm_id,
    pd.stay_id,
    pd.hospital_expire_flag,
    pd.icu_los,
    COALESCE(p.procedure_count, 0) AS procedure_count
  FROM 
    patient_data pd
  LEFT JOIN 
    procedures p ON pd.stay_id = p.stay_id
  WHERE 
    pd.hadm_id IN (SELECT hadm_id FROM ami_patients)
),
quartile_data AS (
  SELECT 
    procedure_count,
    icu_los,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM 
    combined_data
)
SELECT 
  quartile,
  COUNT(*) AS n,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(icu_los) AS mean_icu_los,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_pct
FROM 
  quartile_data
GROUP BY 
  quartile
ORDER BY 
  quartile;