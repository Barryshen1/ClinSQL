WITH pneumonia_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 10 AND (icd_code LIKE 'J12%' OR icd_code LIKE 'J13%' OR icd_code LIKE 'J14%' 
                          OR icd_code LIKE 'J15%' OR icd_code LIKE 'J16%' OR icd_code LIKE 'J17%' 
                          OR icd_code LIKE 'J18%'))
    OR
    (icd_version = 9 AND (icd_code LIKE '480%' OR icd_code LIKE '481%' OR icd_code LIKE '482%' 
                         OR icd_code LIKE '483%' OR icd_code LIKE '484%' OR icd_code LIKE '485%' 
                         OR icd_code LIKE '486%' OR icd_code = '4870'))
),
first_icu AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
base_cohort AS (
  SELECT 
    fi.subject_id,
    fi.hadm_id,
    fi.stay_id,
    fi.intime,
    fi.los,
    adm.admittime,
    pat.gender,
    adm.hospital_expire_flag
  FROM first_icu fi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON fi.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON fi.subject_id = pat.subject_id
  WHERE fi.rn = 1
    AND pat.gender = 'M'
    -- Calculate exact age at admission using timestamp difference
    AND TIMESTAMP_DIFF(adm.admittime, 
                      DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), 
                      YEAR) + pat.anchor_age BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = fi.hadm_id
        AND diag.icd_code IN (
          SELECT icd_code 
          FROM pneumonia_codes 
          WHERE icd_version = diag.icd_version
        )
    )
),
diagnostic_procedures AS (
  SELECT 
    pe.stay_id,
    COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  INNER JOIN base_cohort bc
    ON pe.stay_id = bc.stay_id
  WHERE di.category = 'Diagnostic'
    AND pe.starttime >= bc.intime
    AND pe.starttime <= DATETIME_ADD(bc.intime, INTERVAL 72 HOUR)
  GROUP BY pe.stay_id
),
cohort_with_procs AS (
  SELECT 
    bc.*,
    COALESCE(dp.proc_count, 0) AS proc_count
  FROM base_cohort bc
  LEFT JOIN diagnostic_procedures dp
    ON bc.stay_id = dp.stay_id
),
quintile_assignment AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM cohort_with_procs
)
SELECT
  quintile,
  AVG(proc_count) AS avg_proc_count,
  AVG(los) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct
FROM quintile_assignment
GROUP BY quintile
ORDER BY quintile;