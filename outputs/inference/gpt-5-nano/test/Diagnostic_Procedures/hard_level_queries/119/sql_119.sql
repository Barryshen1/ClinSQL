WITH
-- 1) Define AMI, male, age 42-52, in ICU context
ami_cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = i.subject_id AND di.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
),
-- 2) Per-stay count of distinct procedures in first 72 hours
ami_procs_72h AS (
  SELECT
    ac.subject_id,
    ac.hadm_id,
    ac.stay_id,
    ac.intime,
    ac.admittime,
    ac.dischtime,
    COUNT(DISTINCT pe.itemid) AS distinct_procs_72h
  FROM ami_cohort AS ac
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.hadm_id = ac.hadm_id
   AND pe.stay_id = ac.stay_id
   AND pe.starttime >= ac.intime
   AND pe.starttime < TIMESTAMP_ADD(ac.intime, INTERVAL 72 HOUR)
  GROUP BY
    ac.subject_id,
    ac.hadm_id,
    ac.stay_id,
    ac.intime,
    ac.admittime,
    ac.dischtime
),
-- 3) 90th percentile of the per-stay 72h distinct procedure counts
ami_p90 AS (
  SELECT
    PERCENTILE_CONT(distinct_procs_72h, 0.9) OVER () AS p90_distinct_procs_72h
  FROM ami_procs_72h
  LIMIT 1
),
-- 4) AMI cohort LOS and in-hospital mortality
ami_los_mort AS (
  SELECT
    AVG(TIMESTAMP_DIFF(ac.dischtime, ac.admittime, SECOND)) / 86400.0 AS mean_hosp_los_days,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality_rate
  FROM ami_cohort AS ac
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON ac.hadm_id = a.hadm_id
),
-- 5) Age-matched male comparators (42-52) from ICU
comp_cohort AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),
comp_los_mort AS (
  SELECT
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)) / 86400.0 AS mean_hosp_los_days,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality_rate
  FROM comp_cohort AS cc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON cc.hadm_id = a.hadm_id
)

-- 6) Assemble final output: two rows (AMI group with p90, comparator row without p90)
SELECT
  'AMI_42_52_Male' AS group_label,
  (SELECT p90_distinct_procs_72h FROM ami_p90) AS p90_distinct_procs_72h,
  (SELECT mean_hosp_los_days FROM ami_los_mort) AS mean_hosp_los_days,
  (SELECT in_hospital_mortality_rate FROM ami_los_mort) AS in_hospital_mortality_rate
UNION ALL
SELECT
  'AgeMatchedMale_42_52' AS group_label,
  NULL AS p90_distinct_procs_72h,
  (SELECT mean_hosp_los_days FROM comp_los_mort) AS mean_hosp_los_days,
  (SELECT in_hospital_mortality_rate FROM comp_los_mort) AS in_hospital_mortality_rate;