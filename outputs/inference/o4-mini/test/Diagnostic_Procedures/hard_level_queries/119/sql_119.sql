WITH
-- Base set of male patients aged 42-52 with admissions and ICU stays
male_42_52 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON a.subject_id = icu.subject_id
      AND a.hadm_id    = icu.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),

-- Subset with AMI diagnosis
ami_cohort AS (
  SELECT DISTINCT
    m.subject_id,
    m.hadm_id,
    m.admittime,
    m.dischtime,
    m.hospital_expire_flag,
    icu.stay_id,
    icu.intime
  FROM
    male_42_52 m
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON m.subject_id = d.subject_id
      AND m.hadm_id    = d.hadm_id
      AND d.icd_code LIKE '410%'  -- ICD-9 AMI codes
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON m.subject_id = icu.subject_id
      AND m.hadm_id    = icu.hadm_id
),

-- Compute distinct procedure count in first 72h for each AMI stay
ami_proc_counts AS (
  SELECT
    ac.subject_id,
    ac.hadm_id,
    ac.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM
    ami_cohort ac
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON ac.subject_id = pe.subject_id
      AND ac.hadm_id    = pe.hadm_id
      AND ac.stay_id    = pe.stay_id
      AND pe.starttime BETWEEN ac.intime AND TIMESTAMP_ADD(ac.intime, INTERVAL 72 HOUR)
  GROUP BY
    ac.subject_id,
    ac.hadm_id,
    ac.stay_id
),

-- Statistics for AMI cohort
ami_stats AS (
  SELECT
    -- 90th percentile of distinct procedures in first 72h
    (SELECT
       APPROX_QUANTILES(proc_count, 100)[OFFSET(90)]
     FROM ami_proc_counts
    ) AS p90_proc_count,
    -- Mean hospital LOS in days
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_ami,
    -- In‐hospital mortality rate
    AVG(hospital_expire_flag) AS mort_ami
  FROM
    ami_cohort
),

-- Statistics for all male 42-52 ICU patients
all_stats AS (
  SELECT
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_all,
    AVG(hospital_expire_flag) AS mort_all
  FROM
    male_42_52
)

-- Final output combining both
SELECT
  ami_stats.p90_proc_count,
  ROUND(ami_stats.mean_los_ami, 2) AS mean_los_ami,
  ROUND(ami_stats.mort_ami, 4)     AS mort_rate_ami,
  ROUND(all_stats.mean_los_all, 2) AS mean_los_all,
  ROUND(all_stats.mort_all, 4)     AS mort_rate_all
FROM
  ami_stats,
  all_stats;