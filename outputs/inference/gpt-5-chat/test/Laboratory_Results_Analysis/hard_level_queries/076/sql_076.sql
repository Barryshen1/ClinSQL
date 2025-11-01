WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),
lab_instability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNTIF(LOWER(le.flag) = 'abnormal') AS instability_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND c.hadm_id = le.hadm_id
  WHERE le.charttime >= c.admittime
    AND le.charttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
p95_calc AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_score
  FROM lab_instability
),
high_instability AS (
  SELECT li.*, c.dischtime, c.admittime, c.hospital_expire_flag
  FROM lab_instability li
  JOIN cohort c
    ON li.hadm_id = c.hadm_id
  CROSS JOIN p95_calc p95
  WHERE li.instability_score >= p95.p95_score
),
metrics_high AS (
  SELECT
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
    AVG(hospital_expire_flag) AS in_hosp_mortality_rate,
    AVG(instability_score) AS avg_critical_lab_events_per_patient
  FROM high_instability
),
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNTIF(LOWER(le.flag) = 'abnormal') AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.subject_id = le.subject_id
    AND a.hadm_id = le.hadm_id
  WHERE le.charttime >= a.admittime
    AND le.charttime < DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.subject_id, a.hadm_id
),
metrics_general AS (
  SELECT
    AVG(instability_score) AS avg_critical_lab_events_per_patient
  FROM general_inpatients
)
SELECT
  p95_score,
  mh.mean_los_days,
  mh.in_hosp_mortality_rate,
  mh.avg_critical_lab_events_per_patient AS avg_events_high_group,
  mg.avg_critical_lab_events_per_patient AS avg_events_general_inpatients
FROM p95_calc
CROSS JOIN metrics_high mh
CROSS JOIN metrics_general mg;