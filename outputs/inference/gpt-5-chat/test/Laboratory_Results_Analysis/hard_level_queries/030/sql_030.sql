WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
   AND dx.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(dd.long_title) LIKE '%asthma%'
    AND LOWER(dd.long_title) LIKE '%exacerb%'
),
critical_labs AS (
  SELECT l.hadm_id,
         COUNT(*) AS critical_lab_events
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cohort c
    ON l.hadm_id = c.hadm_id
  WHERE l.flag IS NOT NULL
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY l.hadm_id
),
all_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
all_critical_labs AS (
  SELECT l.hadm_id,
         COUNT(*) AS critical_lab_events
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN all_admissions a
    ON l.hadm_id = a.hadm_id
  WHERE l.flag IS NOT NULL
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY l.hadm_id
),
cohort_with_labs AS (
  SELECT c.*,
         IFNULL(cl.critical_lab_events, 0) AS critical_lab_events
  FROM cohort c
  LEFT JOIN critical_labs cl
    ON c.hadm_id = cl.hadm_id
),
all_with_labs AS (
  SELECT a.*,
         IFNULL(cl.critical_lab_events, 0) AS critical_lab_events
  FROM all_admissions a
  LEFT JOIN all_critical_labs cl
    ON a.hadm_id = cl.hadm_id
),
cohort_stats AS (
  SELECT
    APPROX_QUANTILES(critical_lab_events, 4)[OFFSET(3)] AS p75_lab_instability,
    AVG(los) AS avg_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM cohort_with_labs
),
all_stats AS (
  SELECT
    AVG(critical_lab_events) AS avg_lab_instability,
    AVG(los) AS avg_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM all_with_labs
)
SELECT
  cs.p75_lab_instability,
  cs.avg_los AS cohort_avg_los,
  cs.mortality_rate AS cohort_mortality_rate,
  ast.avg_lab_instability AS all_avg_lab_instability,
  ast.avg_los AS all_avg_los,
  ast.mortality_rate AS all_mortality_rate
FROM cohort_stats cs
JOIN all_stats ast
  ON TRUE;