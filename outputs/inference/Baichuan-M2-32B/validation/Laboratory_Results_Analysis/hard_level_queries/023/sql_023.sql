WITH admissions_with_age AS (
  SELECT 
    a.*,
    p.gender,  -- Added to include gender from patients table
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
),
ami_cohort AS (
  SELECT 
    a.*
  FROM admissions_with_age a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    a.gender = 'F'
    AND a.age_at_admission BETWEEN 90 AND 100
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%') 
      OR 
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
    )
),
entire_cohort AS (
  SELECT 
    a.*
  FROM admissions_with_age a
  WHERE 
    a.age_at_admission BETWEEN 90 AND 100
),
ami_lab_events AS (
  SELECT 
    a.hadm_id,
    l.labevent_id,
    CASE 
      WHEN l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL 
           AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper) THEN 1
      WHEN l.flag IS NOT NULL THEN 1
      ELSE 0 
    END AS is_abnormal
  FROM ami_cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),
ami_instability AS (
  SELECT 
    hadm_id,
    SUM(is_abnormal) AS instability_score
  FROM ami_lab_events
  GROUP BY hadm_id
),
percentile AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75
  FROM ami_instability
),
ami_p75 AS (
  SELECT 
    a.*,
    i.instability_score,
    CASE WHEN i.instability_score >= (SELECT p75 FROM percentile) THEN 1 ELSE 0 END AS is_p75
  FROM ami_cohort a
  LEFT JOIN ami_instability i ON a.hadm_id = i.hadm_id
),
p75_metrics AS (
  SELECT 
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality,
    AVG(TIMESTAMP_DIFF(
          CASE 
            WHEN hospital_expire_flag = 1 THEN deathtime
            ELSE dischtime 
          END, 
          admittime, 
          HOUR) / 24.0) AS mean_los,
    AVG(instability_score) AS critical_lab_rate
  FROM ami_p75
  WHERE 
    is_p75 = 1
    AND (dischtime IS NOT NULL OR hospital_expire_flag = 1)
),
entire_lab_events AS (
  SELECT 
    e.hadm_id,
    l.labevent_id,
    CASE 
      WHEN l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL 
           AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper) THEN 1
      WHEN l.flag IS NOT NULL THEN 1
      ELSE 0 
    END AS is_abnormal
  FROM entire_cohort e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON e.subject_id = l.subject_id AND e.hadm_id = l.hadm_id
    AND l.charttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 48 HOUR)
),
entire_instability AS (
  SELECT 
    hadm_id,
    SUM(is_abnormal) AS instability_score
  FROM entire_lab_events
  GROUP BY hadm_id
),
entire_metrics AS (
  SELECT 
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality,
    AVG(TIMESTAMP_DIFF(
          CASE 
            WHEN hospital_expire_flag = 1 THEN deathtime
            ELSE dischtime 
          END, 
          admittime, 
          HOUR) / 24.0) AS mean_los,
    AVG(instability_score) AS critical_lab_rate
  FROM entire_cohort
  LEFT JOIN entire_instability i ON entire_cohort.hadm_id = i.hadm_id
  WHERE 
    (dischtime IS NOT NULL OR hospital_expire_flag = 1)
)
SELECT 
  (SELECT mortality FROM p75_metrics) AS p75_mortality,
  (SELECT mean_los FROM p75_metrics) AS p75_mean_los,
  (SELECT critical_lab_rate FROM p75_metrics) AS p75_critical_lab_rate,
  (SELECT mortality FROM entire_metrics) AS entire_mortality,
  (SELECT mean_los FROM entire_metrics) AS entire_mean_los,
  (SELECT critical_lab_rate FROM entire_metrics) AS entire_critical_lab_rate;