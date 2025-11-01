WITH age_gender_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 88 AND 98
),
copd_dx AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
    AND dx.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chronic obstructive%'
    AND LOWER(dd.long_title) LIKE '%exacerb%'
),
procedures_first72 AS (
  SELECT
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS proc_count_72h
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN age_gender_icu ag
    ON p.stay_id = ag.stay_id
  WHERE p.starttime >= ag.intime
    AND p.starttime < DATETIME_ADD(ag.intime, INTERVAL 72 HOUR)
  GROUP BY p.stay_id
),
cohort AS (
  SELECT
    ag.*,
    CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS copd_flag,
    COALESCE(pf.proc_count_72h, 0) AS proc_count_72h
  FROM age_gender_icu ag
  LEFT JOIN copd_dx c
    ON ag.hadm_id = c.hadm_id
  LEFT JOIN procedures_first72 pf
    ON ag.stay_id = pf.stay_id
),
stats AS (
  SELECT
    copd_flag,
    AVG(los) AS mean_icu_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort
  GROUP BY copd_flag
),
copd_percentile AS (
  SELECT
    PERCENTILE_CONT(proc_count_72h, 0.75) OVER() AS p75_proc_72h
  FROM cohort
  WHERE copd_flag = 1
)
SELECT
  c75.p75_proc_72h,
  s.*
FROM stats s
CROSS JOIN (SELECT DISTINCT p75_proc_72h FROM copd_percentile) c75
ORDER BY copd_flag DESC;