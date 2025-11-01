WITH patients_icu AS (
  SELECT 
    p.subject_id, 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.los, 
    p.gender, 
    p.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime ASC) AS stay_order
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 83 AND 93
),
first_stays AS (
  SELECT 
    subject_id, 
    stay_id, 
    hadm_id, 
    intime, 
    los
  FROM patients_icu
  WHERE stay_order = 1
),
sepsis_cohorts AS (
  SELECT DISTINCT 
    subject_id, 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (d.icd_version = 10 
         AND d.icd_code IN ('A40.0', 'A40.1', 'A40.3', 'A40.8', 'A40.9', 
                            'A41.01', 'A41.02', 'A41.1', 'A41.2', 'A41.3', 
                            'A41.4', 'A41.50', 'A41.51', 'A41.52', 'A41.53', 
                            'A41.59', 'A41.81', 'A41.89', 'A41.9', 
                            'R65.20', 'R65.21'))
     OR (d.icd_version = 9 
         AND d.icd_code IN ('0380', '03810', '03811', '03812', '03819', 
                            '03840', '03841', '03842', '03843', '03844', 
                            '03849', '0388', '0389', '78552', '99591', '99592'))
),
cohort AS (
  SELECT 
    fs.subject_id, 
    fs.stay_id, 
    fs.hadm_id, 
    fs.intime, 
    fs.los,
    a.hospital_expire_flag
  FROM first_stays fs
  INNER JOIN sepsis_cohorts sc 
    ON fs.subject_id = sc.subject_id 
    AND fs.hadm_id = sc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON fs.hadm_id = a.hadm_id
),
proc_counts AS (
  SELECT 
    c.*,
    COUNT(DISTINCT pe.itemid) AS num_procs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.subject_id = pe.subject_id
    AND c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY 
    c.subject_id, c.stay_id, c.hadm_id, c.intime, c.los, c.hospital_expire_flag
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY num_procs ASC) AS quartile
  FROM proc_counts
)
SELECT 
  quartile,
  ROUND(AVG(num_procs), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(*)), 2) AS mortality_percentage
FROM quartiles
GROUP BY quartile
ORDER BY quartile;