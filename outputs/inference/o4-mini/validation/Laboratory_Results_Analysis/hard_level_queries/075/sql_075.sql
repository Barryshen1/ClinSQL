WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code    = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(dd.long_title) LIKE '%deep vein thrombosi%'
),
lab_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag,
    c.los_days,
    COUNTIF(
      le.valuenum IS NOT NULL
      AND (le.valuenum < le.ref_range_lower
           OR le.valuenum > le.ref_range_upper)
    ) AS critical_labs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
   AND c.hadm_id    = le.hadm_id
   AND le.charttime BETWEEN c.admittime
                       AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.hospital_expire_flag, c.los_days
),
scores AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    los_days,
    critical_labs / 72.0 AS lab_instability_score
  FROM lab_counts
),
pct AS (
  SELECT
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(95)] AS p95
  FROM scores
),
group_metrics AS (
  SELECT
    CASE
      WHEN s.lab_instability_score >= p.p95 THEN '>=95th percentile'
      ELSE '<95th percentile'
    END AS patient_group,
    AVG(s.hospital_expire_flag) AS mortality_rate,
    AVG(s.los_days)            AS mean_los_days,
    AVG(s.lab_instability_score) AS mean_critical_lab_rate
  FROM scores s
  CROSS JOIN pct p
  GROUP BY patient_group
),
overall AS (
  SELECT
    'all_inpatients' AS patient_group,
    NULL                AS mortality_rate,
    NULL                AS mean_los_days,
    AVG(s.lab_instability_score) AS mean_critical_lab_rate
  FROM scores s
)
SELECT * FROM group_metrics
UNION ALL
SELECT * FROM overall
ORDER BY patient_group;