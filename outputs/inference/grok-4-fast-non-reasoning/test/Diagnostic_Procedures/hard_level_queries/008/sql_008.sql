WITH cohort AS (
  -- Base cohort: males aged 48-58 with ICU stay and UGIB admission
  SELECT DISTINCT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'K25%' OR d.icd_code LIKE 'K26%' OR d.icd_code = 'K92.2')
),

first_stay AS (
  -- First ICU stay per subject (min intime)
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    admittime,
    dischtime,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM cohort
  QUALIFY rn = 1
),

procedure_counts AS (
  -- Count distinct diagnostic procedures in first 24h of first ICU stay (includes 0s via LEFT JOIN)
  SELECT 
    fs.subject_id,
    COALESCE(COUNT(DISTINCT pe.itemid), 0) AS diag_proc_count,
    fs.admittime,
    fs.dischtime,
    fs.hospital_expire_flag
  FROM first_stay fs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fs.subject_id = pe.subject_id
    AND fs.hadm_id = pe.hadm_id
    AND fs.stay_id = pe.stay_id
    AND pe.starttime IS NOT NULL
    AND pe.starttime >= fs.intime
    AND pe.starttime < TIMESTAMP_ADD(fs.intime, INTERVAL 24 HOUR)
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE di.category = 'Diagnostic'
  GROUP BY fs.subject_id, fs.admittime, fs.dischtime, fs.hospital_expire_flag
),

quintiles AS (
  SELECT 
    diag_proc_count,
    NTILE(5) OVER (ORDER BY diag_proc_count) AS quintile,
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS hosp_los_days,
    hospital_expire_flag
  FROM procedure_counts
)

SELECT 
  quintile,
  ROUND(AVG(diag_proc_count), 2) AS avg_procedures,
  ROUND(AVG(hosp_los_days), 2) AS avg_hosp_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hosp_mortality_pct,
  COUNT(*) AS n_subjects
FROM quintiles
GROUP BY quintile
ORDER BY quintile;