WITH asthma_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND di.long_title LIKE '%asthma%'
    AND di.long_title LIKE '%exacerbation%'
),

lab_events AS (
  SELECT
    a.hadm_id,
    COUNT(l.labevent_id) AS lab_instability_score
  FROM asthma_cohort a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
  WHERE l.flag IS NOT NULL
  GROUP BY a.hadm_id
),

percentile AS (
  SELECT
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY lab_instability_score) AS p90
  FROM lab_events
),

top_decile AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    le.lab_instability_score
  FROM asthma_cohort a
  JOIN lab_events le ON a.hadm_id = le.hadm_id
  CROSS JOIN percentile p
  WHERE le.lab_instability_score >= p.p90
),

all_males AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

all_lab_events AS (
  SELECT
    a.hadm_id,
    COUNT(l.labevent_id) AS lab_instability_score
  FROM all_males a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
  WHERE l.flag IS NOT NULL
  GROUP BY a.hadm_id
),

top_decile_metrics AS (
  SELECT
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate,
    AVG(los_days) AS mean_los,
    AVG(lab_instability_score) AS avg_critical_lab_events
  FROM top_decile
),

all_males_metrics AS (
  SELECT
    AVG(CAST(a.hospital_expire_flag AS INT64)) AS mortality_rate_all,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_los_all,
    AVG(le.lab_instability_score) AS avg_critical_lab_events_all
  FROM all_males a
  LEFT JOIN all_lab_events le ON a.hadm_id = le.hadm_id
)

SELECT
  t.mortality_rate,
  t.mean_los,
  t.avg_critical_lab_events,
  a.mortality_rate_all,
  a.mean_los_all,
  a.avg_critical_lab_events_all
FROM top_decile_metrics t
CROSS JOIN all_males_metrics a;