WITH first_stays AS (
  -- Identify first ICU stay per patient
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year,
    -- Approximate age at admission
    SAFE_CAST(pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year AS INT64) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) = 1
),
base_cohort AS (
  -- Base cohort: females, age 66-76, first stay
  SELECT 
    fs.*,
    -- Flag sepsis: any relevant ICD code in the admission
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        WHERE diag.subject_id = fs.subject_id 
          AND diag.hadm_id = fs.hadm_id
          AND (
            (diag.icd_version = 9 AND (diag.icd_code LIKE '038%' OR diag.icd_code = '99591'))
            OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'A40%' OR diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R65%'))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_sepsis
  FROM first_stays fs
  WHERE fs.gender = 'F'
    AND fs.age_at_adm BETWEEN 66 AND 76
),
sepsis_cohort AS (
  -- Sepsis subgroup
  SELECT *
  FROM base_cohort
  WHERE has_sepsis = 1
),
control_cohort AS (
  -- Control subgroup (no sepsis)
  SELECT *
  FROM base_cohort
  WHERE has_sepsis = 0
),
procedure_counts AS (
  -- Distinct procedures in first 48h for sepsis cohort
  SELECT 
    sc.subject_id,
    COUNT(DISTINCT pe.itemid) AS num_distinct_procedures
  FROM sepsis_cohort sc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON sc.subject_id = pe.subject_id
    AND sc.hadm_id = pe.hadm_id
    AND sc.stay_id = pe.stay_id
  WHERE pe.starttime >= sc.intime
    AND pe.starttime < TIMESTAMP_ADD(sc.intime, INTERVAL 48 HOUR)
    AND pe.statusdescription != 'Canceled'
  GROUP BY sc.subject_id
),
p90_procedures AS (
  -- 90th percentile (default to 0 if no procedures)
  SELECT 
    APPROX_PERCENTILE_CONT(COALESCE(num_distinct_procedures, 0), 0.9) AS p90_num_procedures
  FROM (
    SELECT subject_id, num_distinct_procedures
    FROM sepsis_cohort
    LEFT JOIN procedure_counts USING (subject_id)
  )
),
group_summaries AS (
  -- LOS and mortality summaries
  SELECT 
    'Sepsis Cohort' AS group_name,
    has_sepsis,
    COUNT(*) AS n_patients,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_hospital_los_days,
    SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) * 100 AS mortality_rate_percent
  FROM base_cohort
  WHERE has_sepsis = 1
  GROUP BY has_sepsis
  
  UNION ALL
  
  SELECT 
    'Control Cohort' AS group_name,
    has_sepsis,
    COUNT(*) AS n_patients,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_hospital_los_days,
    SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) * 100 AS mortality_rate_percent
  FROM base_cohort
  WHERE has_sepsis = 0
  GROUP BY has_sepsis
)
-- Final output: combine percentile with summaries
SELECT 
  gs.group_name,
  gs.n_patients,
  gs.mean_hospital_los_days,
  gs.mortality_rate_percent,
  pp90.p90_num_procedures  -- Sepsis-specific 90th percentile of distinct procedures (first 48h)
FROM group_summaries gs
CROSS JOIN p90_procedures pp90
ORDER BY 
  CASE WHEN gs.group_name = 'Sepsis Cohort' THEN 1 ELSE 2 END
;