WITH first_icu AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),
pneumonia_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dc
    ON d.icd_code = dc.icd_code AND d.icd_version = dc.icd_version
  WHERE dc.long_title LIKE '%pneumonia%'
),
proc_counts AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.los,
    (SELECT COUNT(*)
     FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
     WHERE p.stay_id = f.stay_id
       AND p.starttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
    ) AS proc_count
  FROM first_icu f
  WHERE f.rn = 1
    AND f.hadm_id IN (SELECT hadm_id FROM pneumonia_hadm)
),
mortality_data AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.proc_count,
    p.los,
    a.hospital_expire_flag
  FROM proc_counts p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM mortality_data
)
SELECT 
  quintile,
  AVG(proc_count) AS avg_proc_count,
  AVG(los) AS avg_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;