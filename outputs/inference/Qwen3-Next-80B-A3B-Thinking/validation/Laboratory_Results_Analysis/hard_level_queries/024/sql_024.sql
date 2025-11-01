WITH cardiac_arrest_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND d_icd.long_title LIKE '%cardiac arrest%'
),

lab_events AS (
  SELECT
    c.hadm_id,
    COUNT(l.labevent_id) AS lab_instability_score
  FROM cardiac_arrest_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '48' HOUR
  WHERE l.flag IS NOT NULL
  GROUP BY c.hadm_id
),

percentile AS (
  SELECT
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY lab_instability_score) AS p90
  FROM lab_events
),

all_inpatients AS (
  SELECT
    AVG(lab_count) AS avg_critical_labs_all
  FROM (
    SELECT
      a.hadm_id,
      COUNT(l.labevent_id) AS lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
      ON a.hadm_id = l.hadm_id
      AND l.charttime BETWEEN a.admittime AND a.admittime + INTERVAL '48' HOUR
    WHERE l.flag IS NOT NULL
    GROUP BY a.hadm_id
  )
),

high_risk AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    l.lab_instability_score
  FROM cardiac_arrest_cohort c
  JOIN lab_events l ON c.hadm_id = l.hadm_id
  WHERE l.lab_instability_score >= (SELECT p90 FROM percentile)
)

SELECT
  COUNT(*) AS count_high_risk,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
  AVG(lab_instability_score) AS avg_critical_labs_high_risk,
  (SELECT avg_critical_labs_all FROM all_inpatients) AS avg_critical_labs_all
FROM high_risk;