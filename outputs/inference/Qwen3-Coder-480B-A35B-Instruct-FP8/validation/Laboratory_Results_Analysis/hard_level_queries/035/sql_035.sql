WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND dd.icd_code LIKE 'I63%'
    AND i.intime >= a.admittime
),

lab_events_72h AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.labevent_id,
    l.valuenum,
    l.flag,
    l.charttime,
    c.stay_id
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    c.subject_id = l.subject_id
  WHERE
    l.charttime >= c.intime
    AND l.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
),

instability_scores AS (
  SELECT
    subject_id,
    stay_id,
    STDDEV_POP(valuenum) AS instability_score
  FROM
    lab_events_72h
  GROUP BY
    subject_id, stay_id
),

min_instability AS (
  SELECT
    MIN(instability_score) AS min_instability_score
  FROM
    instability_scores
),

cohort_lab_summary AS (
  SELECT
    c.subject_id,
    COUNT(l.labevent_id) AS total_labs,
    SUM(CASE WHEN l.flag = 'abnormal' THEN 1 ELSE 0 END) AS abnormal_labs
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    c.subject_id = l.subject_id
  GROUP BY
    c.subject_id
),

avg_cohort_abnormal AS (
  SELECT
    AVG(abnormal_labs) AS avg_abnormal_labs_per_patient
  FROM
    cohort_lab_summary
),

general_inpatient_labs AS (
  SELECT
    l.subject_id,
    COUNT(l.labevent_id) AS total_labs,
    SUM(CASE WHEN l.flag = 'abnormal' THEN 1 ELSE 0 END) AS abnormal_labs
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  GROUP BY
    l.subject_id
),

avg_general_abnormal AS (
  SELECT
    AVG(abnormal_labs) AS avg_abnormal_labs_general
  FROM
    general_inpatient_labs
),

cohort_stats AS (
  SELECT
    AVG(icu_los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
  FROM
    cohort
)

SELECT
  (SELECT min_instability_score FROM min_instability) AS min_72h_lab_instability_score,
  (SELECT avg_abnormal_labs_per_patient FROM avg_cohort_abnormal) AS avg_abnormal_labs_cohort,
  (SELECT avg_abnormal_labs_general FROM avg_general_abnormal) AS avg_abnormal_labs_general,
  (SELECT avg_icu_los FROM cohort_stats) AS avg_icu_los,
  (SELECT in_hospital_mortality_rate FROM cohort_stats) AS in_hospital_mortality_rate;