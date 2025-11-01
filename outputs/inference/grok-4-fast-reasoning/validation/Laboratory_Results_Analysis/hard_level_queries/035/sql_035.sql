WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND FLOOR(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code IN ('43310', '43311', '43321', '43331', '43391', '43401', '43411', '43491', '436'))
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I63%')
        )
    )
),
cohort_abnormal_labs AS (
  SELECT 
    le.hadm_id,
    COUNT(*) AS count_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN cohort c ON le.hadm_id = c.hadm_id
  WHERE le.flag IN ('L', 'H', 'abnormal')
    AND le.charttime >= c.admittime
    AND le.charttime < c.admittime + INTERVAL 72 HOUR
  GROUP BY le.hadm_id
),
cohort_metrics AS (
  SELECT 
    c.hadm_id,
    COALESCE(cal.count_abnormal, 0) AS instability_score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN cohort_abnormal_labs cal ON c.hadm_id = cal.hadm_id
),
all_admissions AS (
  SELECT 
    hadm_id,
    admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IS NOT NULL
),
all_abnormal_labs AS (
  SELECT 
    le.hadm_id,
    COUNT(*) AS count_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN all_admissions aa ON le.hadm_id = aa.hadm_id
  WHERE le.flag IN ('L', 'H', 'abnormal')
    AND le.charttime >= aa.admittime
    AND le.charttime < aa.admittime + INTERVAL 72 HOUR
  GROUP BY le.hadm_id
),
general_metrics AS (
  SELECT 
    aa.hadm_id,
    COALESCE(aal.count_abnormal, 0) AS instability_score
  FROM all_admissions aa
  LEFT JOIN all_abnormal_labs aal ON aa.hadm_id = aal.hadm_id
)
SELECT 
  MIN(instability_score) AS minimum_72_hour_laboratory_instability_score,
  AVG(instability_score) AS cohort_average_critical_lab_events,
  (SELECT AVG(instability_score) FROM general_metrics) AS general_average_critical_lab_events,
  AVG(los_days) AS cohort_average_los_days,
  (SUM(hospital_expire_flag) / COUNT(*) * 100) AS cohort_in_hospital_mortality_percentage
FROM cohort_metrics;