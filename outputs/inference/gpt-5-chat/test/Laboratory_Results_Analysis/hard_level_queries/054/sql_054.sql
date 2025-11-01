WITH female_age_range AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
ami_flags AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    1 AS is_ami
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE ( (d.icd_version = 9 AND d.icd_code LIKE '410%')
       OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%') )
  GROUP BY subject_id, hadm_id
),
cohort AS (
  SELECT
    f.*,
    IF(ami.is_ami = 1, 1, 0) AS is_ami
  FROM female_age_range f
  LEFT JOIN ami_flags ami
    ON f.subject_id = ami.subject_id
    AND f.hadm_id = ami.hadm_id
),
critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cohort c
    ON l.subject_id = c.subject_id
    AND l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (
      (l.valuenum IS NOT NULL AND l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL
         AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper))
      OR (LOWER(l.flag) LIKE '%abnormal%')
    )
  GROUP BY l.subject_id, l.hadm_id
),
cohort_with_score AS (
  SELECT
    c.*,
    COALESCE(cl.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN critical_labs cl
    ON c.subject_id = cl.subject_id
    AND c.hadm_id = cl.hadm_id
),
ami_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
  FROM cohort_with_score
  WHERE is_ami = 1
),
quartile_summary AS (
  SELECT
    instability_quartile,
    COUNT(*) AS n_admissions,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM ami_quartiles
  GROUP BY instability_quartile
  ORDER BY instability_quartile
),
overall_critical_rate AS (
  SELECT
    CASE WHEN is_ami = 1 THEN 'AMI' ELSE 'Control' END AS group_type,
    AVG(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM cohort_with_score
  GROUP BY group_type
)
-- Final output: quartile stats + critical lab rate table
SELECT 'QUARTILE_SUMMARY' AS table_type, * 
FROM quartile_summary
UNION ALL
SELECT 'CRITICAL_LAB_RATE' AS table_type,
       NULL AS instability_quartile,
       NULL AS n_admissions,
       NULL AS avg_los_days,
       NULL AS mortality_rate,
FROM overall_critical_rate;