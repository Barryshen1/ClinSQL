WITH hemorrhagic_stroke_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('430','431','432'))
    OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),

all_admissions_48_58F AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
),

hemorrhagic_admissions_48_58F AS (
  SELECT a.*
  FROM all_admissions_48_58F a
  INNER JOIN hemorrhagic_stroke_admissions h
    ON a.hadm_id = h.hadm_id
),

hemorrhagic_lab_metrics AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COUNT(DISTINCT le.itemid) AS instability_score,
    COUNT(le.labevent_id) AS total_critical_labs
  FROM hemorrhagic_admissions_48_58F a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
    AND le.charttime >= a.admittime
    AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

p90_value AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90
  FROM hemorrhagic_lab_metrics
),

high_instability_group AS (
  SELECT *
  FROM hemorrhagic_lab_metrics, p90_value
  WHERE instability_score >= p90
),

non_hemorrhagic_admissions_48_58F AS (
  SELECT a.*
  FROM all_admissions_48_58F a
  LEFT JOIN hemorrhagic_stroke_admissions h
    ON a.hadm_id = h.hadm_id
  WHERE h.hadm_id IS NULL
),

cohort_lab_metrics AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COUNT(le.labevent_id) AS total_critical_labs
  FROM non_hemorrhagic_admissions_48_58F a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
    AND le.charttime >= a.admittime
    AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

high_instability_metrics AS (
  SELECT 
    'high_instability_group' AS group_name,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(total_critical_labs) AS avg_critical_labs
  FROM high_instability_group
),

cohort_metrics AS (
  SELECT 
    'age_matched_cohort' AS group_name,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(total_critical_labs) AS avg_critical_labs
  FROM cohort_lab_metrics
)

SELECT * FROM high_instability_metrics
UNION ALL
SELECT * FROM cohort_metrics;