WITH eligible_patients AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 37 AND 47
),
first_icu_stays AS (
  SELECT subject_id, stay_id, hadm_id, intime, outtime, los
  FROM (
    SELECT icu.*, 
           ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN eligible_patients ep ON icu.subject_id = ep.subject_id
  )
  WHERE rn = 1
),
procedure_counts AS (
  SELECT 
    fis.subject_id,
    fis.stay_id,
    fis.hadm_id,
    fis.los,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM first_icu_stays fis
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = fis.subject_id
    AND pe.hadm_id = fis.hadm_id
    AND pe.stay_id = fis.stay_id
    AND pe.starttime >= fis.intime
    AND pe.starttime < TIMESTAMP_ADD(fis.intime, INTERVAL 2 DAY)
  GROUP BY fis.subject_id, fis.stay_id, fis.hadm_id, fis.los
),
stratified_data AS (
  SELECT 
    pc.*,
    COALESCE(a.hospital_expire_flag, 0) AS hospital_expire_flag,
    NTILE(5) OVER (ORDER BY pc.proc_count ASC) AS quintile
  FROM procedure_counts pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = pc.hadm_id
)
SELECT 
  quintile,
  ROUND(AVG(proc_count), 2) AS mean_proc_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_rate_pct
FROM stratified_data
GROUP BY quintile
ORDER BY quintile;