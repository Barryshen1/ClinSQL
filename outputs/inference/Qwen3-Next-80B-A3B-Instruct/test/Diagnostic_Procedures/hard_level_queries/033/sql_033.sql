WITH first_icu_stay AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS stay_seq
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
first_icu_procedures AS (
  SELECT 
    fis.subject_id,
    fis.stay_id,
    fis.hadm_id,
    fis.intime,
    fis.los,
    COUNT(*) AS procedure_count
  FROM first_icu_stay fis
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fis.stay_id = pe.stay_id
  WHERE fis.stay_seq = 1
    AND pe.starttime >= fis.intime
    AND pe.starttime <= TIMESTAMP_ADD(fis.intime, INTERVAL 48 HOUR)
    AND pe.starttime IS NOT NULL
  GROUP BY fis.subject_id, fis.stay_id, fis.hadm_id, fis.intime, fis.los
),
quintiles AS (
  SELECT 
    fip.subject_id,
    fip.procedure_count,
    fip.los,
    a.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY fip.procedure_count) AS quintile
  FROM first_icu_procedures fip
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fip.hadm_id = a.hadm_id
)
SELECT 
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;