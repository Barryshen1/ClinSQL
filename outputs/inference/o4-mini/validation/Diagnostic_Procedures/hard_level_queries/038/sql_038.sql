WITH first_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      USING(subject_id, hadm_id)
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) = 1
),
ich_adm AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    first_icu f
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING(icd_code, icd_version)
  WHERE
    LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
),
proc_counts AS (
  SELECT
    f.stay_id,
    COUNT(*) AS proc_count
  FROM
    first_icu f
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
      ON p.stay_id = f.stay_id
  WHERE
    p.starttime BETWEEN f.intime
                    AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY
    f.stay_id
)
SELECT
  cohort,
  -- 75th percentile of procedure counts in first 72h
  APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS p75_proc_count,
  -- Mean ICU length of stay (days)
  AVG(los) AS mean_icu_los_days,
  -- Hospital mortality rate
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.los,
    f.hospital_expire_flag,
    COALESCE(pc.proc_count, 0) AS proc_count,
    pt.gender,
    pt.anchor_age,
    CASE
      WHEN pt.gender = 'M'
       AND pt.anchor_age BETWEEN 60 AND 70
       AND ich.subject_id IS NOT NULL
      THEN 'ICH_cohort'
      ELSE 'General'
    END AS cohort
  FROM
    first_icu f
    LEFT JOIN proc_counts pc
      ON pc.stay_id = f.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
      ON pt.subject_id = f.subject_id
    LEFT JOIN ich_adm ich
      ON ich.subject_id = f.subject_id
     AND ich.hadm_id    = f.hadm_id
)
GROUP BY
  cohort
ORDER BY
  cohort;