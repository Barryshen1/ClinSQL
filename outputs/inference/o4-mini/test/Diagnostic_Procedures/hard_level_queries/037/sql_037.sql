WITH sepsis_hadm AS (
  SELECT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%sepsis%'
  GROUP BY
    d.hadm_id
),

icu_base AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag,
    CASE
      WHEN sepsis_hadm.hadm_id IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_sepsis
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id
      AND icu.hadm_id = adm.hadm_id
    LEFT JOIN sepsis_hadm
      ON icu.hadm_id = sepsis_hadm.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),

proc_counts AS (
  SELECT
    ib.subject_id,
    ib.hadm_id,
    ib.stay_id,
    COUNT(pe.subject_id) AS proc_count
  FROM
    icu_base ib
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON ib.subject_id = pe.subject_id
      AND ib.hadm_id = pe.hadm_id
      AND ib.stay_id = pe.stay_id
      AND pe.starttime BETWEEN ib.intime 
        AND TIMESTAMP_ADD(ib.intime, INTERVAL 24 HOUR)
  GROUP BY
    ib.subject_id,
    ib.hadm_id,
    ib.stay_id
)

SELECT
  CASE 
    WHEN ib.is_sepsis THEN 'sepsis' 
    ELSE 'all_age_matched' 
  END AS cohort,
  -- 75th and 90th percentiles of procedure counts
  APPROX_QUANTILES(pc.proc_count, 100)[OFFSET(75)] AS pct_75_proc_count,
  APPROX_QUANTILES(pc.proc_count, 100)[OFFSET(90)] AS pct_90_proc_count,
  -- average ICU length of stay
  AVG(ib.los) AS avg_icu_los,
  -- hospital mortality rate
  AVG(ib.hospital_expire_flag) AS hospital_mortality_rate
FROM
  icu_base ib
  JOIN proc_counts pc
    ON ib.subject_id = pc.subject_id
    AND ib.hadm_id = pc.hadm_id
    AND ib.stay_id = pc.stay_id
GROUP BY
  cohort
ORDER BY
  cohort;