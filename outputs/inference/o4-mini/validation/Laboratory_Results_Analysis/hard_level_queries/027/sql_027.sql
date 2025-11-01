WITH lower_gi_admissions AS (
  -- 1. Cohort: male patients 89-99 with lower GI bleed
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
         AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND LOWER(dicd.long_title) LIKE '%lower gastrointestinal bleeding%'
    AND a.hospital_expire_flag IS NOT NULL
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age
),

labs_first_72 AS (
  -- 2. All lab events in the first 72h of those admissions
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    CASE
      WHEN l.valuenum IS NOT NULL
       AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      THEN 1 ELSE 0
    END AS is_critical
  FROM
    lower_gi_admissions g
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON g.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN g.admittime
      AND TIMESTAMP_ADD(g.admittime, INTERVAL 72 HOUR)
),

lab_summary AS (
  -- 3. Summarize per admission: instability score & total labs
  SELECT
    hadm_id,
    COUNT(*) AS total_labs_72h,
    SUM(is_critical) AS instability_score
  FROM labs_first_72
  GROUP BY hadm_id
),

quintiled AS (
  -- 4. Assign quintile based on instability_score
  SELECT
    g.hadm_id,
    g.admittime,
    g.dischtime,
    g.hospital_expire_flag,
    ls.instability_score,
    ls.total_labs_72h,
    NTILE(5) OVER (ORDER BY ls.instability_score) AS quintile
  FROM
    lower_gi_admissions g
    JOIN lab_summary ls
      ON g.hadm_id = ls.hadm_id
),

quintile_metrics AS (
  -- 5. Compute per-quintile metrics for the bleed cohort
  SELECT
    quintile,
    COUNT(*) AS n_admissions,
    AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    SUM(instability_score) / SUM(total_labs_72h) AS lab_critical_rate
  FROM quintiled
  GROUP BY quintile
),

-- 6. General rate among all male 89-99 inpatients
general_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.hospital_expire_flag IS NOT NULL
),

general_labs_72 AS (
  SELECT
    l.hadm_id,
    CASE
      WHEN l.valuenum IS NOT NULL
       AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      THEN 1 ELSE 0
    END AS is_critical
  FROM
    general_cohort g
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON g.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN g.admittime
      AND TIMESTAMP_ADD(g.admittime, INTERVAL 72 HOUR)
),

general_summary AS (
  SELECT
    SUM(is_critical) AS total_critical,
    COUNT(*) AS total_labs
  FROM general_labs_72
)

-- 7. Final output: quintiles + general rate
SELECT
  CAST(quintile AS STRING) AS group_label,
  n_admissions AS admissions,
  avg_los_days,
  mortality_rate,
  lab_critical_rate
FROM quintile_metrics

UNION ALL

SELECT
  'General_89_99_M' AS group_label,
  NULL AS admissions,
  NULL AS avg_los_days,
  NULL AS mortality_rate,
  total_critical / total_labs AS lab_critical_rate
FROM general_summary

ORDER BY
  group_label;