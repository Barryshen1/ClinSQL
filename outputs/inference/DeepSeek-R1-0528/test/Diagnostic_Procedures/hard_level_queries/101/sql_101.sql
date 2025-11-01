WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime,  -- Added missing column
    i.los,
    adm.hospital_expire_flag,
    -- Flag for COPD exacerbation (J441)
    MAX(CASE WHEN diag.icd_code = 'J441' AND diag.icd_version = 10 THEN 1 ELSE 0 END) AS copd_ex_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON i.hadm_id = adm.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON i.hadm_id = diag.hadm_id
    AND diag.icd_code = 'J441'
    AND diag.icd_version = 10
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
  GROUP BY p.subject_id, p.anchor_age, i.hadm_id, i.stay_id, i.intime, i.los, adm.hospital_expire_flag
),
cases_with_procedures AS (
  SELECT 
    c.stay_id,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  WHERE c.copd_ex_flag = 1
  GROUP BY c.stay_id
)

-- Final Output
SELECT 
  (SELECT 
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] 
   FROM cases_with_procedures
  ) AS percentile_75_procedures,
  -- Mean ICU LOS (per stay) and Mortality (per admission) for COPD cohort
  (SELECT AVG(los) FROM cohort WHERE copd_ex_flag = 1) AS mean_los_copd,
  (SELECT AVG(hospital_expire_flag) FROM cohort WHERE copd_ex_flag = 1) AS mortality_rate_copd,
  -- Same for control cohort
  (SELECT AVG(los) FROM cohort WHERE copd_ex_flag = 0) AS mean_los_control,
  (SELECT AVG(hospital_expire_flag) FROM cohort WHERE copd_ex_flag = 0) AS mortality_rate_control;