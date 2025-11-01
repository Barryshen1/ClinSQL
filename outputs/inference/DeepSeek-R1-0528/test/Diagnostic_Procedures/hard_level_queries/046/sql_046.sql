WITH first_icu_stay AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id,
    intime,
    outtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_order
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
proc_counts AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM first_icu_stay icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON icu.stay_id = pe.stay_id
    AND pe.starttime >= icu.intime
    AND pe.starttime <= DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
  WHERE icu.stay_order = 1
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),
cohort AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.num_procedures,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los
  FROM proc_counts pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pc.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pc.hadm_id = a.hadm_id
),
ards_diagnosis AS (
  SELECT 
    hadm_id,
    MAX(CASE 
        WHEN (icd_version = 9 AND icd_code = '518.82') 
          OR (icd_version = 10 AND icd_code = 'J80') 
        THEN 1 ELSE 0 
    END) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_with_ards AS (
  SELECT 
    c.*,
    COALESCE(a.has_ards, 0) AS has_ards,
    -- Compute age at hospital admission
    c.anchor_age + (EXTRACT(YEAR FROM c.admittime) - c.anchor_year) AS age_at_admission
  FROM cohort c
  LEFT JOIN ards_diagnosis a
    ON c.hadm_id = a.hadm_id
),
case_cohort AS (
  SELECT num_procedures
  FROM cohort_with_ards
  WHERE 
    gender = 'F' 
    AND age_at_admission BETWEEN 37 AND 47
    AND has_ards = 1
),
control_cohort AS (
  SELECT 
    num_procedures,
    hosp_los,
    hospital_expire_flag
  FROM cohort_with_ards
),
control_metrics AS (
  SELECT 
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75_procedures,
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] AS p90_procedures,
    AVG(hosp_los) AS mean_hosp_los,
    AVG(hospital_expire_flag) AS in_hosp_mortality  -- Fixed: Removed redundant CAST
  FROM control_cohort
)
SELECT
  (SELECT MIN(num_procedures) FROM case_cohort) AS min_procedures_case,
  p75_procedures AS p75_procedures_control,
  p90_procedures AS p90_procedures_control,
  mean_hosp_los AS mean_hosp_los_control,
  in_hosp_mortality AS in_hosp_mortality_control
FROM control_metrics;