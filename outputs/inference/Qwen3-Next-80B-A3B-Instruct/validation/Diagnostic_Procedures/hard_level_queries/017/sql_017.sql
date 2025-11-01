WITH first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
),
sepsis_patients AS (
  SELECT DISTINCT
    d.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%sepsis%'
    AND LOWER(dicd.long_title) NOT LIKE '%screening%'
    AND LOWER(dicd.long_title) NOT LIKE '%suspected%'
    AND LOWER(dicd.long_title) NOT LIKE '%rule out%'
),
male_83_93 AS (
  SELECT 
    p.subject_id,
    p.anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),
first_icu_sepsis_male AS (
  SELECT 
    fis.subject_id,
    fis.stay_id,
    fis.hadm_id,
    fis.intime,
    fis.los,
    a.hospital_expire_flag
  FROM first_icu_stay fis
  JOIN sepsis_patients sp ON fis.subject_id = sp.subject_id
  JOIN male_83_93 m ON fis.subject_id = m.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON fis.hadm_id = a.hadm_id
  WHERE fis.rn = 1
),
first_72h_procedures AS (
  SELECT 
    pe.subject_id,
    pe.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
  JOIN first_icu_sepsis_male fis ON pe.subject_id = fis.subject_id AND pe.stay_id = fis.stay_id
  WHERE pe.starttime >= fis.intime 
    AND pe.starttime <= DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
  GROUP BY pe.subject_id, pe.stay_id
),
quartiles AS (
  SELECT 
    fis.subject_id,
    COALESCE(f72.proc_count, 0) AS proc_count,
    fis.los,
    fis.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY COALESCE(f72.proc_count, 0)) AS quartile
  FROM first_icu_sepsis_male fis
  LEFT JOIN first_72h_procedures f72 ON fis.subject_id = f72.subject_id AND fis.stay_id = f72.stay_id
)
SELECT 
  quartile,
  AVG(proc_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;