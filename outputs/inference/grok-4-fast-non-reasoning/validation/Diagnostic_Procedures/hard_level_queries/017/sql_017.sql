WITH sepsis_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = '10' 
    AND (icd_code LIKE 'A41%' OR icd_code LIKE 'R65%')
),
first_icu_stays AS (
  SELECT 
    icu.subject_id,
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.subject_id = diag.subject_id AND icu.hadm_id = diag.hadm_id
  INNER JOIN sepsis_codes sc
    ON diag.icd_code = sc.icd_code AND diag.icd_version = '10'
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 83 AND 93
  QUALIFY rn = 1  -- First ICU stay only
),
procedures_72h AS (
  SELECT 
    fis.stay_id,
    fis.intime,
    COUNT(DISTINCT proc.itemid) AS procedure_count
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON fis.subject_id = proc.subject_id 
    AND fis.hadm_id = proc.hadm_id 
    AND fis.stay_id = proc.stay_id
    AND proc.starttime >= fis.intime
    AND proc.starttime <= TIMESTAMP_ADD(fis.intime, INTERVAL 72 HOUR)
  GROUP BY fis.stay_id, fis.intime
),
cohort_with_procs AS (
  SELECT 
    fis.*,
    COALESCE(p72.procedure_count, 0) AS procedure_count
  FROM first_icu_stays fis
  LEFT JOIN procedures_72h p72
    ON fis.stay_id = p72.stay_id
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM cohort_with_procs
),
summary AS (
  SELECT 
    quartile,
    ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
    ROUND(AVG(los), 2) AS mean_los_days,
    ROUND(AVG(CASE WHEN adm.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100, 2) AS mortality_pct
  FROM quartiles q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON q.subject_id = adm.subject_id AND q.hadm_id = adm.hadm_id
  GROUP BY quartile
)
SELECT 
  CONCAT('Q', quartile) AS quartile,
  mean_procedure_count,
  mean_los_days,
  mortality_pct
FROM summary
ORDER BY quartile;