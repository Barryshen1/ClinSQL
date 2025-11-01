WITH first_icu_stays AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
sepsis_diagnoses AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%sepsis%' 
     OR LOWER(d.long_title) LIKE '%septicemia%'
     OR di.icd_code IN ('995.91', '995.92', 'A41.9', 'R65.20', 'R65.21', 'R65.22')
),
patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    fi.stay_id,
    fi.intime,
    fi.los AS icu_los,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN first_icu_stays fi 
    ON p.subject_id = fi.subject_id AND fi.rn = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id AND fi.hadm_id = a.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 66 AND 76
),
sepsis_cohort AS (
  SELECT DISTINCT 
    pf.subject_id,
    pf.hadm_id,
    pf.intime,
    pf.hospital_expire_flag,
    DATETIME_DIFF(pf.dischtime, pf.admittime, DAY) AS hospital_los
  FROM patients_filtered pf
  JOIN sepsis_diagnoses sd 
    ON pf.subject_id = sd.subject_id AND pf.hadm_id = sd.hadm_id
),
control_cohort AS (
  SELECT DISTINCT 
    pf.subject_id,
    pf.hadm_id,
    pf.intime,
    pf.hospital_expire_flag,
    DATETIME_DIFF(pf.dischtime, pf.admittime, DAY) AS hospital_los
  FROM patients_filtered pf
  LEFT JOIN sepsis_diagnoses sd 
    ON pf.subject_id = sd.subject_id AND pf.hadm_id = sd.hadm_id
  WHERE sd.subject_id IS NULL
),
procedures_in_48h AS (
  SELECT 
    pe.stay_id,
    pe.itemid,
    pe.starttime
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN sepsis_cohort sc 
    ON pe.stay_id = sc.stay_id
  WHERE pe.starttime >= sc.intime 
    AND pe.starttime <= sc.intime + INTERVAL 48 HOUR
),
distinct_procedures_per_patient AS (
  SELECT 
    sc.subject_id,
    COUNT(DISTINCT pi.itemid) AS num_distinct_procedures
  FROM sepsis_cohort sc
  LEFT JOIN procedures_in_48h pi 
    ON sc.stay_id = pi.stay_id
  GROUP BY sc.subject_id
),
sepsis_summary AS (
  SELECT 
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY dpp.num_distinct_procedures) AS p90_procedures_sepsis,
    AVG(sc.hospital_los) AS avg_los_sepsis,
    AVG(CAST(sc.hospital_expire_flag AS FLOAT64)) AS mortality_rate_sepsis
  FROM distinct_procedures_per_patient dpp
  JOIN sepsis_cohort sc 
    ON dpp.subject_id = sc.subject_id
),
control_summary AS (
  SELECT 
    AVG(cc.hospital_los) AS avg_los_control,
    AVG(CAST(cc.hospital_expire_flag AS FLOAT64)) AS mortality_rate_control
  FROM control_cohort cc
)
SELECT 
  s.p90_procedures_sepsis,
  s.avg_los_sepsis,
  s.mortality_rate_sepsis,
  c.avg_los_control,
  c.mortality_rate_control
FROM sepsis_summary s
CROSS JOIN control_summary c;