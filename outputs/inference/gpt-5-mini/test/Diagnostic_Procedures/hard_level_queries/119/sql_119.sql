WITH
-- Identify ICU stays for male patients age 42-52
male_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id AND s.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE
    UPPER(p.gender) = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),

-- Admissions for male patients age 42-52 that had an ICU stay
male_admissions_with_icu AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    UPPER(p.gender) = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` s
      WHERE s.hadm_id = a.hadm_id
    )
    AND a.dischtime IS NOT NULL
),

-- Admissions with AMI diagnosis (ICD9 410.* or ICD10 I21*/I22*)
ami_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '410%')
    OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
),

-- AMI cohort: male admissions (age 42-52) that had an ICU stay and have AMI
ami_admissions_with_icu AS (
  SELECT a.*
  FROM male_admissions_with_icu a
  WHERE a.hadm_id IN (SELECT hadm_id FROM ami_admissions)
),

-- Comparator: male admissions (age 42-52) that had an ICU stay but DO NOT have AMI
age_matched_no_ami_admissions AS (
  SELECT a.*
  FROM male_admissions_with_icu a
  WHERE NOT EXISTS (
    SELECT 1 FROM ami_admissions am WHERE am.hadm_id = a.hadm_id
  )
),

-- Per-ICU-stay diagnostic intensity (distinct procedures in first 72 ICU hours) for AMI stays
ami_stay_proc_counts AS (
  SELECT
    s.stay_id,
    s.hadm_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN ami_admissions_with_icu a
    ON s.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = s.stay_id
    AND pe.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.stay_id, s.hadm_id
),

-- Also compute per-ICU-stay counts for comparator group (optional, for completeness)
comp_stay_proc_counts AS (
  SELECT
    s.stay_id,
    s.hadm_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN age_matched_no_ami_admissions a
    ON s.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = s.stay_id
    AND pe.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.stay_id, s.hadm_id
),

-- Admission-level LOS and mortality for AMI admissions (one row per hadm_id)
ami_admission_stats AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days,
    CAST(hospital_expire_flag AS INT64) AS died_in_hosp
  FROM ami_admissions_with_icu
),

-- Admission-level LOS and mortality for comparator admissions (no AMI)
comp_admission_stats AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days,
    CAST(hospital_expire_flag AS INT64) AS died_in_hosp
  FROM age_matched_no_ami_admissions
)

-- Final aggregation: produce one row for AMI cohort and one for age-matched males without AMI
SELECT
  'AMI_males_42_52' AS cohort,
  (SELECT COUNT(*) FROM ami_stay_proc_counts) AS n_icustays,
  -- 90th percentile diagnostic intensity (distinct procedures in first 72 ICU hours) for AMI cohort
  (SELECT APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] FROM ami_stay_proc_counts) AS p90_proc_count,
  (SELECT COUNT(*) FROM ami_admission_stats) AS n_admissions,
  (SELECT AVG(los_days) FROM ami_admission_stats) AS mean_los_days,
  (SELECT AVG(died_in_hosp) FROM ami_admission_stats) AS inhospital_mortality_rate
UNION ALL
SELECT
  'Age_matched_males_without_AMI_42_52' AS cohort,
  (SELECT COUNT(*) FROM comp_stay_proc_counts) AS n_icustays,
  NULL AS p90_proc_count,
  (SELECT COUNT(*) FROM comp_admission_stats) AS n_admissions,
  (SELECT AVG(los_days) FROM comp_admission_stats) AS mean_los_days,
  (SELECT AVG(died_in_hosp) FROM comp_admission_stats) AS inhospital_mortality_rate
;