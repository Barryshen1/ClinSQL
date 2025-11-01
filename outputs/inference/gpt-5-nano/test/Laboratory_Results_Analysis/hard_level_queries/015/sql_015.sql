WITH stroke_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 3600.0) AS los_hours,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND di.icd_code LIKE 'I63%'
    AND di.icd_version = 9
  GROUP BY
    a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    p.gender, p.anchor_age
),

-- 2) Compute 72-hour lab metrics per admission
labs72 AS (
  SELECT
    sa.hadm_id,
    sa.subject_id,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag AS mortality_flag,
    sa.los_hours,
    sa.gender,
    sa.anchor_age,
    COALESCE(STDDEV_POP(le.valuenum), 0) AS instability,
    COUNT(le.valuenum) AS total_lab_events72h,
    SUM(CASE
          WHEN ((le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                OR
                (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper))
          THEN 1 ELSE 0 END) AS critical_lab_events72h
  FROM stroke_admissions sa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = sa.subject_id
   AND le.hadm_id = sa.hadm_id
   AND le.charttime BETWEEN sa.admittime AND TIMESTAMP_ADD(sa.admittime, INTERVAL 72 HOUR)
  GROUP BY
    sa.hadm_id, sa.subject_id, sa.admittime, sa.dischtime,
    sa.hospital_expire_flag, sa.los_hours, sa.gender, sa.anchor_age
),

-- 3) Compute derived metrics per admission
computed AS (
  SELECT
    l.*,
    CASE
      WHEN l.total_lab_events72h > 0 THEN l.critical_lab_events72h * 1.0 / l.total_lab_events72h
      ELSE 0
    END AS critical_rate
  FROM labs72 l
),

-- 4) Determine 75th percentile instability threshold from the cohort
threshold AS (
  SELECT APPROX_QUANTILES(instability, 100)[OFFSET(74)] AS p75_instability
  FROM computed
),

-- 5) Classify into high-instability vs controls and summarize
final AS (
  SELECT
    CASE
      WHEN instability >= t.p75_instability THEN 'High instability'
      ELSE 'Control'
    END AS group_name,
    COUNT(*) AS n_admissions,
    AVG(los_hours) AS mean_los_hours,
    AVG(mortality_flag) AS mortality_rate,
    AVG(critical_rate) AS mean_critical_lab_rate
  FROM computed c
  CROSS JOIN threshold t
  GROUP BY group_name
  ORDER BY group_name
)

SELECT * FROM final;