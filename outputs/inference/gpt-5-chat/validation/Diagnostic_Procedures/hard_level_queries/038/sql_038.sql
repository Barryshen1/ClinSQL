WITH first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
),
first_icu_only AS (
  SELECT f.subject_id, f.hadm_id, f.stay_id, f.intime, f.outtime, f.los
  FROM first_icu f
  WHERE f.rn = 1
),
diag_ich AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%intracerebral hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%subarachnoid hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%subdural hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%epidural hemorrhage%'
),
proc_counts AS (
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.stay_id,
    COUNT(pe.itemid) AS proc_burden_72h
  FROM first_icu_only fi
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fi.stay_id = pe.stay_id
    AND pe.starttime >= fi.intime
    AND pe.starttime < TIMESTAMP_ADD(fi.intime, INTERVAL 72 HOUR)
  GROUP BY fi.subject_id, fi.hadm_id, fi.stay_id
),
cohort AS (
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.stay_id,
    p.gender,
    p.anchor_age,
    adm.hospital_expire_flag,
    fi.los,
    COALESCE(pc.proc_burden_72h, 0) AS proc_burden_72h,
    CASE WHEN ich.subject_id IS NOT NULL THEN 1 ELSE 0 END AS ich_flag
  FROM first_icu_only fi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fi.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON fi.hadm_id = adm.hadm_id
  LEFT JOIN proc_counts pc
    ON fi.subject_id = pc.subject_id AND fi.stay_id = pc.stay_id
  LEFT JOIN diag_ich ich
    ON fi.subject_id = ich.subject_id AND fi.hadm_id = ich.hadm_id
),
ich_group AS (
  SELECT *
  FROM cohort
  WHERE gender = 'M' AND anchor_age BETWEEN 60 AND 70 AND ich_flag = 1
),
summary_ich AS (
  SELECT
    'ICH_male_60_70' AS grp,
    APPROX_QUANTILES(proc_burden_72h, 100)[OFFSET(75)] AS p75_proc_burden,
    AVG(los) AS mean_icu_los_days,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
  FROM ich_group
),
summary_all AS (
  SELECT
    'general_icu' AS grp,
    NULL AS p75_proc_burden,
    AVG(los) AS mean_icu_los_days,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
  FROM cohort
)
SELECT * FROM summary_ich
UNION ALL
SELECT * FROM summary_all;