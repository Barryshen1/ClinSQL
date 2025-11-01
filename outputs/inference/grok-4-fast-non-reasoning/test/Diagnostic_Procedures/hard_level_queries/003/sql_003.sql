WITH first_stays AS (
  SELECT *
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) = 1
),
patients_stays AS (
  SELECT 
    fs.stay_id, fs.subject_id, fs.hadm_id, fs.intime, fs.los AS icu_los,
    p.gender, p.anchor_age
  FROM first_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fs.subject_id = p.subject_id
),
admissions_stays AS (
  SELECT 
    ps.*,
    a.admittime, a.dischtime, a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los
  FROM patients_stays ps
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ps.hadm_id = a.hadm_id
),
ards_cohort AS (
  SELECT DISTINCT 
    asj.subject_id, asj.hadm_id
  FROM admissions_stays asj
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON asj.subject_id = di.subject_id AND asj.hadm_id = di.hadm_id
  WHERE (di.icd_code LIKE '518.5%' OR di.icd_code LIKE 'J80%')
    AND asj.gender = 'F' 
    AND asj.anchor_age BETWEEN 84 AND 94
),
procedures_first24_ards AS (
  SELECT 
    ast.stay_id, ast.subject_id, ast.hadm_id,
    COUNT(DISTINCT pe.itemid) AS procedure_intensity
  FROM admissions_stays ast
  INNER JOIN ards_cohort ac 
    ON ast.subject_id = ac.subject_id AND ast.hadm_id = ac.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ast.subject_id = pe.subject_id 
    AND ast.hadm_id = pe.hadm_id 
    AND ast.stay_id = pe.stay_id
    AND pe.starttime >= ast.intime 
    AND pe.starttime < TIMESTAMP_ADD(ast.intime, INTERVAL 24 HOUR)
  WHERE ast.gender = 'F' 
    AND ast.anchor_age BETWEEN 84 AND 94
    AND ast.hospital_los IS NOT NULL
  GROUP BY ast.stay_id, ast.subject_id, ast.hadm_id
),
procedures_first24_general AS (
  SELECT 
    ast.stay_id, ast.subject_id, ast.hadm_id,
    COUNT(DISTINCT pe.itemid) AS procedure_intensity
  FROM admissions_stays ast
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ast.subject_id = pe.subject_id 
    AND ast.hadm_id = pe.hadm_id 
    AND ast.stay_id = pe.stay_id
    AND pe.starttime >= ast.intime 
    AND pe.starttime < TIMESTAMP_ADD(ast.intime, INTERVAL 24 HOUR)
  WHERE ast.gender = 'F' 
    AND ast.anchor_age BETWEEN 84 AND 94
    AND ast.hospital_los IS NOT NULL
  GROUP BY ast.stay_id, ast.subject_id, ast.hadm_id
),
cohort_data AS (
  SELECT 
    'ARDS' AS cohort,
    p24.procedure_intensity,
    ast.hospital_los,
    ast.hospital_expire_flag
  FROM procedures_first24_ards p24
  INNER JOIN admissions_stays ast 
    ON p24.stay_id = ast.stay_id

  UNION ALL

  SELECT 
    'General' AS cohort,
    p24.procedure_intensity,
    ast.hospital_los,
    ast.hospital_expire_flag
  FROM procedures_first24_general p24
  INNER JOIN admissions_stays ast 
    ON p24.stay_id = ast.stay_id
)
SELECT 
  cohort,
  PERCENTILE_CONT(0.25) OVER (PARTITION BY cohort) AS p25_intensity,
  PERCENTILE_CONT(0.75) OVER (PARTITION BY cohort) AS p75_intensity,
  PERCENTILE_CONT(0.95) OVER (PARTITION BY cohort) AS p95_intensity,
  AVG(hospital_los) AS avg_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM cohort_data
GROUP BY cohort
ORDER BY 
  CASE WHEN cohort = 'ARDS' THEN 1 ELSE 2 END;