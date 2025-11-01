WITH ich_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los_days,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.subject_id = dx.subject_id
   AND icu.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
    AND (
         (dx.icd_version = 9 AND (
              dx.icd_code LIKE '430%' OR
              dx.icd_code LIKE '431%' OR
              dx.icd_code LIKE '432%'))
      OR (dx.icd_version = 10 AND (
              dx.icd_code LIKE 'I60%' OR
              dx.icd_code LIKE 'I61%' OR
              dx.icd_code LIKE 'I62%'))
        )
),
proc_counts AS (
  SELECT
    coh.subject_id,
    coh.hadm_id,
    coh.stay_id,
    COUNT(pe.itemid) AS procedure_count,
    coh.icu_los_days,
    coh.hospital_expire_flag
  FROM ich_cohort coh
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON coh.subject_id = pe.subject_id
    AND coh.stay_id = pe.stay_id
    AND pe.starttime >= coh.intime
    AND pe.starttime < DATETIME_ADD(coh.intime, INTERVAL 72 HOUR)
  GROUP BY coh.subject_id, coh.hadm_id, coh.stay_id, coh.icu_los_days, coh.hospital_expire_flag
),
ich_summary AS (
  SELECT
    -- Percentiles from procedure_count
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS proc_count_p25,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS proc_count_p50,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS proc_count_p90,
    AVG(icu_los_days) AS avg_icu_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM proc_counts
),
general_icu AS (
  SELECT
    AVG(los) AS avg_icu_los_days,
    AVG(CAST(adm.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id = adm.hadm_id
)
SELECT
  'ICH Female 50-60' AS cohort,
  proc_count_p25,
  proc_count_p50,
  proc_count_p90,
  avg_icu_los_days,
  mortality_rate
FROM ich_summary
UNION ALL
SELECT
  'General ICU' AS cohort,
  NULL AS proc_count_p25,
  NULL AS proc_count_p50,
  NULL AS proc_count_p90,
  avg_icu_los_days,
  mortality_rate
FROM general_icu;