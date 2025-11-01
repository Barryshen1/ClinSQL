WITH first_icu_stays AS (
  -- First ICU stay per subject
  SELECT 
    subject_id,
    stay_id,
    hadm_id,
    first_careunit,
    intime,
    outtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY stay_id) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE stay_id IS NOT NULL
),

patients_first_stay AS (
  -- Female patients aged 66-76 in first ICU stay
  SELECT 
    fis.*,
    p.gender,
    p.anchor_age
  FROM first_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fis.subject_id = p.subject_id
  WHERE fis.rn = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
),

sepsis_cohort AS (
  -- Sepsis cases: first stay with sepsis diagnosis
  SELECT DISTINCT
    pfs.stay_id,
    pfs.hadm_id,
    pfs.intime
  FROM patients_first_stay pfs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pfs.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE (
    -- ICD-9 sepsis codes
    (di.icd_version = 9 AND (
      di.icd_code LIKE '038.%' OR
      di.icd_code LIKE '785.5%' OR
      di.icd_code = '020.0' OR di.icd_code = '022.3' OR di.icd_code = '036.2' OR
      di.icd_code = '790.7'
    ))
    OR
    -- ICD-10 sepsis codes
    (di.icd_version = 10 AND (
      di.icd_code LIKE 'A40.%' OR
      di.icd_code LIKE 'A41.%' OR
      di.icd_code LIKE 'A42.%' OR
      di.icd_code LIKE 'R65.%'
    ))
  )
),

control_cohort AS (
  -- Controls: first stay without sepsis, same demographics
  SELECT 
    pfs.stay_id,
    pfs.hadm_id,
    pfs.intime
  FROM patients_first_stay pfs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pfs.hadm_id = a.hadm_id
  WHERE pfs.hadm_id NOT IN (SELECT hadm_id FROM sepsis_cohort)
),

all_cohorts AS (
  SELECT stay_id, hadm_id, intime, 'sepsis' AS cohort
  FROM sepsis_cohort
  UNION ALL
  SELECT stay_id, hadm_id, intime, 'control' AS cohort
  FROM control_cohort
),

procedures_sepsis AS (
  -- Distinct procedures in first 48h for sepsis cohort
  SELECT 
    sc.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM sepsis_cohort sc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON sc.stay_id = pe.stay_id
  WHERE pe.starttime BETWEEN sc.intime AND TIMESTAMP_ADD(sc.intime, INTERVAL 48 HOUR)
    AND pe.itemid IS NOT NULL
    AND pe.value IS NOT NULL  -- Indicates procedure occurred
  GROUP BY sc.stay_id
),

p90_procedures AS (
  -- 90th percentile for sepsis
  SELECT 
    PERCENTILE_CONT(distinct_procedures, 0.9) OVER() AS p90_distinct_procedures
  FROM procedures_sepsis
),

outcomes AS (
  -- Hospital LOS and mortality by cohort
  SELECT 
    ac.cohort,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los_days,
    a.hospital_expire_flag AS mortality
  FROM all_cohorts ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ac.hadm_id = a.hadm_id
  WHERE a.dischtime IS NOT NULL  -- Exclude ongoing admissions
)

-- Final results: Procedures percentile + outcomes comparison
SELECT 
  'sepsis' AS cohort,
  (SELECT p90_distinct_procedures FROM p90_procedures) AS p90_distinct_procedures_48h,
  AVG(o.hospital_los_days) AS avg_hospital_los_days,
  AVG(o.mortality) AS mortality_rate
FROM outcomes o
WHERE o.cohort = 'sepsis'

UNION ALL

SELECT 
  'control' AS cohort,
  NULL AS p90_distinct_procedures_48h,  -- Not computed for controls
  AVG(o.hospital_los_days) AS avg_hospital_los_days,
  AVG(o.mortality) AS mortality_rate
FROM outcomes o
WHERE o.cohort = 'control';