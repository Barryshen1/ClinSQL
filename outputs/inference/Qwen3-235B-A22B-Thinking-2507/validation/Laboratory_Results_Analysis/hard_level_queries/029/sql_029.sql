WITH 
admissions_with_age AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),

cohort_base AS (
  SELECT 
    hadm_id, 
    subject_id, 
    admittime
  FROM admissions_with_age
  WHERE gender = 'F'
    AND age_at_admit >= 50
    AND age_at_admit <= 60
),

cohort_hhs AS (
  SELECT DISTINCT 
    c.hadm_id, 
    c.subject_id, 
    c.admittime
  FROM cohort_base c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  WHERE d.icd_version = 10
    AND d.icd_code IN ('E0801', 'E0802', 'E0901', 'E0902', 'E1001', 'E1002', 'E1101', 'E1102', 'E1301', 'E1302')
),

instability_scores AS (
  SELECT 
    c.hadm_id,
    COUNT(l.labevent_id) AS instability_score
  FROM cohort_hhs c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.flag = 'abnormal'
  GROUP BY c.hadm_id
),

percentile_calc AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75
  FROM instability_scores
),

high_instability AS (
  SELECT 
    i.hadm_id
  FROM instability_scores i
  CROSS JOIN percentile_calc p
  WHERE i.instability_score >= p.p75
),

high_instability_metrics AS (
  SELECT 
    AVG(a.hospital_expire_flag) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_los_days,
    COUNT(DISTINCT CASE WHEN l.labevent_id IS NOT NULL THEN a.hadm_id END) / COUNT(DISTINCT a.hadm_id) AS critical_lab_rate
  FROM high_instability hi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON hi.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.flag = 'abnormal'
),

general_critical_lab_rate AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN l.labevent_id IS NOT NULL THEN a.hadm_id END) / COUNT(DISTINCT a.hadm_id) AS critical_lab_rate_general
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.flag = 'abnormal'
)

SELECT 
  mortality_rate,
  mean_los_days,
  critical_lab_rate AS critical_lab_rate_high,
  (SELECT critical_lab_rate_general FROM general_critical_lab_rate) AS critical_lab_rate_general
FROM high_instability_metrics;