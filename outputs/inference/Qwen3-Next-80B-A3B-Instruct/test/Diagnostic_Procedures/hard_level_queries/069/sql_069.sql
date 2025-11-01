WITH pe_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND LOWER(d_icd.long_title) LIKE '%pulmonary embolism%'
),

first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN pe_patients pe ON i.subject_id = pe.subject_id AND i.hadm_id = pe.hadm_id
  WHERE i.intime IS NOT NULL
),

procedures_in_first_72h AS (
  SELECT 
    fis.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM first_icu_stay fis
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON fis.stay_id = pe.stay_id
  WHERE pe.starttime >= fis.intime
    AND pe.starttime <= fis.intime + INTERVAL '72' HOUR
    AND pe.starttime IS NOT NULL
  GROUP BY fis.stay_id
),

final_cohort AS (
  SELECT 
    pe.subject_id,
    pe.hadm_id,
    fis.stay_id,
    COALESCE(pif.procedure_count, 0) AS procedure_count,
    a.dischtime - a.admittime AS hospital_los,
    a.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY COALESCE(pif.procedure_count, 0)) AS quintile
  FROM pe_patients pe
  INNER JOIN first_icu_stay fis ON pe.subject_id = fis.subject_id AND pe.hadm_id = fis.hadm_id AND fis.rn = 1
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON pe.hadm_id = a.hadm_id
  LEFT JOIN procedures_in_first_72h pif ON fis.stay_id = pif.stay_id
)

SELECT 
  quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(EXTRACT(DAY FROM hospital_los) + EXTRACT(HOUR FROM hospital_los)/24.0) AS avg_hospital_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_percent
FROM final_cohort
GROUP BY quintile
ORDER BY quintile;