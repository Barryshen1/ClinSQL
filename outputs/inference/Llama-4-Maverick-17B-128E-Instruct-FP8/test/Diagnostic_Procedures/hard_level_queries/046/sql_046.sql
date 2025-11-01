WITH 
-- Step 1: Filter patients and identify first ICU stay for ARDS patients
ards_patients AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    ie.hadm_id,
    ie.stay_id,
    ie.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 37 AND 47
    AND ie.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code IN ('J80')  -- Assuming J80 is the ICD-10 code for ARDS
    )
    AND ie.intime = (
      SELECT MIN(intime) 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` ie2 
      WHERE ie2.subject_id = p.subject_id
    )
),
-- Step 2: Calculate diagnostic utilization for ARDS patients
ards_procedures AS (
  SELECT 
    ap.subject_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM 
    ards_patients ap
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON ap.stay_id = pe.stay_id
  WHERE 
    pe.starttime <= ap.intime + INTERVAL 3 DAY
  GROUP BY 
    ap.subject_id
),
-- Step 3: Calculate statistics for ARDS patients and all ICU patients
all_procedures AS (
  SELECT 
    ie.subject_id,
    ie.stay_id,
    ie.intime,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON ie.stay_id = pe.stay_id AND pe.starttime <= ie.intime + INTERVAL 3 DAY
  WHERE 
    ie.intime = (
      SELECT MIN(intime) 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` ie2 
      WHERE ie2.subject_id = ie.subject_id
    )
  GROUP BY 
    ie.subject_id, ie.stay_id, ie.intime
),
-- Hospital LOS and mortality for ARDS patients
ards_outcomes AS (
  SELECT 
    ap.subject_id,
    a.dischtime - a.admittime AS hospital_los,
    a.hospital_expire_flag AS in_hospital_mortality
  FROM 
    ards_patients ap
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON ap.hadm_id = a.hadm_id
)
-- Final query to calculate required statistics
SELECT 
  -- P75/P90 of diagnostic utilization for ARDS patients
  APPROX_QUANTILES(ap.distinct_procedures, 100)[OFFSET(75)] AS p75_ards,
  APPROX_QUANTILES(ap.distinct_procedures, 100)[OFFSET(90)] AS p90_ards,
  -- Mean hospital LOS for ARDS patients
  AVG(ao.hospital_los) AS mean_hospital_los_ards,
  -- In-hospital mortality for ARDS patients
  AVG(ao.in_hospital_mortality) AS in_hospital_mortality_ards,
  -- P75/P90 of diagnostic utilization for all ICU patients
  APPROX_QUANTILES(allp.distinct_procedures, 100)[OFFSET(75)] AS p75_all,
  APPROX_QUANTILES(allp.distinct_procedures, 100)[OFFSET(90)] AS p90_all
FROM 
  ards_procedures ap
INNER JOIN 
  ards_outcomes ao ON ap.subject_id = ao.subject_id
CROSS JOIN 
  all_procedures allp;