WITH ich_diagnoses AS (
  -- Identify admissions with intracranial hemorrhage
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code = '431')
    OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I61'))
),
ich_female_stays AS (
  -- ICU stays for female patients aged 50–60 with ICH
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON p.subject_id = adm.subject_id
    JOIN ich_diagnoses ich
      ON adm.subject_id = ich.subject_id
     AND adm.hadm_id    = ich.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON adm.subject_id = icu.subject_id
     AND adm.hadm_id    = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),
ich_proc_counts AS (
  -- Count procedures in first 72h for each stay
  SELECT
    s.stay_id,
    COUNT(*) AS proc_count
  FROM
    ich_female_stays s
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON s.subject_id = pe.subject_id
     AND s.hadm_id    = pe.hadm_id
     AND pe.starttime BETWEEN s.intime 
                         AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY
    s.stay_id
),
ich_cohort_stats AS (
  -- Compute percentiles, median LOS, mortality for the cohort
  SELECT
    -- Procedure burden percentiles (zero if no procedures)
    APPROX_QUANTILES(IFNULL(pc.proc_count, 0), 100)[OFFSET(25)] AS proc_p25,
    APPROX_QUANTILES(IFNULL(pc.proc_count, 0), 100)[OFFSET(50)] AS proc_p50,
    APPROX_QUANTILES(IFNULL(pc.proc_count, 0), 100)[OFFSET(90)] AS proc_p90,
    -- Median ICU LOS
    APPROX_QUANTILES(s.los, 100)[OFFSET(50)] AS los_median,
    -- In-hospital mortality rate
    AVG(s.hospital_expire_flag) AS mortality_rate
  FROM
    ich_female_stays s
    LEFT JOIN ich_proc_counts pc
      ON s.stay_id = pc.stay_id
),
general_icu_stats AS (
  -- Compute median LOS and mortality for all ICU stays
  SELECT
    APPROX_QUANTILES(icu.los, 100)[OFFSET(50)] AS los_median,
    AVG(adm.hospital_expire_flag) AS mortality_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id    = adm.hadm_id
)
-- Final combined report
SELECT
  'ICH F 50-60' AS cohort,
  proc_p25,
  proc_p50,
  proc_p90,
  los_median,
  mortality_rate
FROM
  ich_cohort_stats

UNION ALL

SELECT
  'General ICU' AS cohort,
  NULL AS proc_p25,
  NULL AS proc_p50,
  NULL AS proc_p90,
  los_median,
  mortality_rate
FROM
  general_icu_stats;