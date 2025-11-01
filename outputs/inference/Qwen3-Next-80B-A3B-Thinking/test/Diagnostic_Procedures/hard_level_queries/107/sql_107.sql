WITH pe_hadm AS (
  SELECT DISTINCT d_icd_diagnoses.icd_code, diagnoses_icd.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diagnoses_icd
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd_diagnoses
    ON diagnoses_icd.icd_code = d_icd_diagnoses.icd_code
    AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
  WHERE d_icd_diagnoses.long_title LIKE '%pulmonary embolism%'
),
pe_patients AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    a.hadm_id, 
    a.hospital_expire_flag
  FROM pe_hadm
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pe_hadm.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),
first_icu_stay AS (
  SELECT 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN pe_patients p
    ON i.hadm_id = p.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
),
diagnostic_procedures AS (
  SELECT 
    f.stay_id,
    COUNT(pe.itemid) AS proc_count
  FROM first_icu_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE di.category = 'Diagnostic'
    AND pe.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY f.stay_id
),
patient_data AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.hospital_expire_flag,
    f.los,
    COALESCE(dp.proc_count, 0) AS proc_count
  FROM pe_patients p
  JOIN first_icu_stay f
    ON p.hadm_id = f.hadm_id
  LEFT JOIN diagnostic_procedures dp
    ON f.stay_id = dp.stay_id
),
quartiles AS (
  SELECT 
    NTILE(4) OVER (ORDER BY proc_count) AS quartile,
    proc_count,
    los,
    hospital_expire_flag
  FROM patient_data
)
SELECT 
  quartile,
  COUNT(*) AS N,
  AVG(proc_count) AS mean_proc_count,
  AVG(los) AS mean_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_pct
FROM quartiles
GROUP BY quartile
ORDER BY quartile;