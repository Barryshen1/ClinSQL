WITH first_stays AS (
  SELECT *
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
patients_join AS (
  SELECT fs.*, p.gender, p.anchor_age
  FROM first_stays fs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fs.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
sepsis_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
admissions_join AS (
  SELECT 
    pj.*,
    a.hospital_expire_flag,
    CASE WHEN sh.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_sepsis
  FROM patients_join pj
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pj.hadm_id = a.hadm_id
  LEFT JOIN sepsis_hadm sh
    ON pj.hadm_id = sh.hadm_id
),
proc_counts AS (
  SELECT 
    pe.stay_id,
    COUNT(*) AS num_procs
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN first_stays fs
    ON pe.stay_id = fs.stay_id
  WHERE pe.starttime >= fs.intime
    AND pe.starttime < DATETIME_ADD(fs.intime, INTERVAL 24 HOUR)
  GROUP BY pe.stay_id
)
SELECT 
  has_sepsis,
  CASE WHEN has_sepsis = 1 THEN 'With Sepsis' ELSE 'Without Sepsis (Age-Matched)' END AS cohort,
  APPROX_QUANTILES(num_procs, 101)[OFFSET(75)] AS p75_procedures,
  APPROX_QUANTILES(num_procs, 101)[OFFSET(90)] AS p90_procedures,
  AVG(los) AS avg_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
FROM (
  SELECT 
    aj.has_sepsis,
    aj.los,
    aj.hospital_expire_flag,
    COALESCE(pc.num_procs, 0) AS num_procs
  FROM admissions_join aj
  LEFT JOIN proc_counts pc
    ON aj.stay_id = pc.stay_id
)
GROUP BY has_sepsis
ORDER BY has_sepsis DESC;