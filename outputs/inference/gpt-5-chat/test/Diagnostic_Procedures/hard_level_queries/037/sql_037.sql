WITH sepsis_dx AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
icu_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.anchor_age,
    pat.gender,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag,
    CASE WHEN sd.subject_id IS NOT NULL THEN 1 ELSE 0 END AS sepsis_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
  LEFT JOIN sepsis_dx sd
    ON icu.subject_id = sd.subject_id AND icu.hadm_id = sd.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
),
proc_counts AS (
  SELECT
    coh.stay_id,
    coh.sepsis_flag,
    coh.los,
    coh.hospital_expire_flag,
    COUNT(*) AS proc_count
  FROM icu_cohort coh
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON coh.stay_id = pe.stay_id
    AND pe.starttime IS NOT NULL
    AND TIMESTAMP_DIFF(pe.starttime, coh.intime, HOUR) BETWEEN 0 AND 24
  GROUP BY coh.stay_id, coh.sepsis_flag, coh.los, coh.hospital_expire_flag
),
summary AS (
  SELECT
    sepsis_flag,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS p75_proc_count,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS p90_proc_count,
    AVG(los) AS avg_icu_los_days,
    AVG(hospital_expire_flag) AS hosp_mortality_rate
  FROM proc_counts
  GROUP BY sepsis_flag
)
SELECT
  CASE WHEN sepsis_flag = 1 THEN 'Sepsis' ELSE 'Non-sepsis' END AS group_label,
  p75_proc_count,
  p90_proc_count,
  avg_icu_los_days,
  hosp_mortality_rate
FROM summary
ORDER BY sepsis_flag DESC;