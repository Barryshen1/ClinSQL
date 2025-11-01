WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    i.stay_id, 
    i.intime, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.anchor_age,
    FLOOR(EXTRACT(YEAR FROM a.admittime) - (2008 - p.anchor_age)) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND FLOOR(EXTRACT(YEAR FROM a.admittime) - (2008 - p.anchor_age)) BETWEEN 82 AND 92
),
first_stay AS (
  SELECT *, 
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
  FROM cohort
),
eligible_stays AS (
  SELECT * 
  FROM first_stay 
  WHERE rn = 1
),
shock_patients AS (
  SELECT DISTINCT es.*
  FROM eligible_stays es
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.subject_id = es.subject_id 
      AND d.hadm_id = es.hadm_id
      AND (
        (d.icd_version = 9 AND d.icd_code = '785.51')
        OR (d.icd_version = 10 AND d.icd_code = 'R57.0')
      )
  )
),
procs AS (
  SELECT 
    sp.subject_id, 
    sp.stay_id, 
    sp.hadm_id,
    COUNT(pe.itemid) AS procedure_count
  FROM shock_patients sp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON sp.subject_id = pe.subject_id 
    AND sp.stay_id = pe.stay_id
    AND pe.starttime >= sp.intime
    AND pe.starttime < TIMESTAMP_ADD(sp.intime, INTERVAL 1 DAY)
  GROUP BY sp.subject_id, sp.stay_id, sp.hadm_id
),
los_mort AS (
  SELECT 
    pr.*,
    (TIMESTAMP_DIFF(sp.dischtime, sp.admittime, SECOND) / 86400.0) AS los_days,
    sp.hospital_expire_flag
  FROM procs pr
  INNER JOIN shock_patients sp
    ON pr.subject_id = sp.subject_id 
    AND pr.stay_id = sp.stay_id
),
quintiles AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM los_mort
)
SELECT 
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los_days) AS mean_hospital_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100 AS mortality_percentage
FROM quintiles
GROUP BY quintile
ORDER BY quintile;