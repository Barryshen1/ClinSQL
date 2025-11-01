WITH eligible_patients AS (
  -- Patients aged 82-92, male
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
),

first_icustays AS (
  -- First ICU stay per admission for eligible patients
  SELECT 
    fis.subject_id,
    fis.hadm_id,
    fis.stay_id,
    fis.intime,
    fis.outtime,
    ROW_NUMBER() OVER (PARTITION BY fis.hadm_id ORDER BY fis.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` fis
  INNER JOIN eligible_patients ep ON fis.subject_id = ep.subject_id
  WHERE fis.intime IS NOT NULL
    AND fis.outtime IS NOT NULL
),

shock_cohort AS (
  -- Add cardiogenic shock filter
  SELECT 
    fis.*,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM first_icustays fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fis.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON fis.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON di.icd_code = icd.icd_code 
    AND di.icd_version = icd.icd_version
  WHERE fis.rn = 1  -- First stay only
    AND LOWER(icd.long_title) LIKE '%cardiogenic shock%'
),

procedures_24h AS (
  -- Procedures in first 24h of ICU stay
  SELECT 
    sc.subject_id,
    sc.hadm_id,
    sc.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM shock_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON sc.subject_id = pe.subject_id
    AND sc.hadm_id = pe.hadm_id
    AND sc.stay_id = pe.stay_id
    AND (pe.starttime BETWEEN sc.intime AND TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR)
         OR (pe.starttime IS NULL AND pe.endtime BETWEEN sc.intime AND TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR)))
  GROUP BY sc.subject_id, sc.hadm_id, sc.stay_id
),

cohort_with_procs AS (
  -- Base cohort with procedures (default to 0 if no procedures)
  SELECT 
    sc.subject_id,
    sc.hadm_id,
    sc.stay_id,
    COALESCE(p24.procedure_count, 0) AS procedure_count,
    DATE_DIFF(sc.dischtime, sc.admittime, DAY) AS hospital_los_days,
    sc.hospital_expire_flag
  FROM shock_cohort sc
  LEFT JOIN procedures_24h p24 ON sc.subject_id = p24.subject_id 
    AND sc.hadm_id = p24.hadm_id 
    AND sc.stay_id = p24.stay_id
)

-- Stratify into quintiles and aggregate
SELECT 
  quintile,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(hospital_los_days), 2) AS mean_hospital_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percentage
FROM (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM cohort_with_procs
)
GROUP BY quintile
ORDER BY quintile;