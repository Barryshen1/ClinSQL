WITH
-- COPD exacerbation cohort
copd_cohort AS (
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
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(dd.long_title) LIKE '%copd%'
    AND LOWER(dd.long_title) LIKE '%exacerb%'
),

-- Age‐matched ICU cohort without requiring COPD
all_cohort AS (
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
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),

-- Compute per‐stay distinct procedure counts in first 72h
proc_counts AS (
  SELECT
    'COPD' AS cohort,
    cc.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count,
    cc.los,
    cc.hospital_expire_flag
  FROM copd_cohort cc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = cc.subject_id
   AND pe.hadm_id    = cc.hadm_id
   AND pe.stay_id    = cc.stay_id
   AND pe.starttime BETWEEN cc.intime AND cc.intime + INTERVAL 72 HOUR
  GROUP BY
    cc.stay_id,
    cc.los,
    cc.hospital_expire_flag

  UNION ALL

  SELECT
    'All' AS cohort,
    ac.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count,
    ac.los,
    ac.hospital_expire_flag
  FROM all_cohort ac
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = ac.subject_id
   AND pe.hadm_id    = ac.hadm_id
   AND pe.stay_id    = ac.stay_id
   AND pe.starttime BETWEEN ac.intime AND ac.intime + INTERVAL 72 HOUR
  GROUP BY
    ac.stay_id,
    ac.los,
    ac.hospital_expire_flag
),

-- Aggregate per‐cohort statistics, computing the quantile array
cohort_stats AS (
  SELECT
    cohort,
    APPROX_QUANTILES(proc_count, 100) AS q_arr,
    AVG(los) AS mean_icu_los,
    SAFE_DIVIDE(
      SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END),
      COUNT(*)
    ) AS in_hospital_mortality
  FROM proc_counts
  GROUP BY cohort
)

-- Final select extracting the 75th percentile from the quantile array
SELECT
  cohort,
  q_arr[OFFSET(75)] AS p75_proc_count,
  mean_icu_los,
  in_hospital_mortality
FROM cohort_stats
ORDER BY cohort;