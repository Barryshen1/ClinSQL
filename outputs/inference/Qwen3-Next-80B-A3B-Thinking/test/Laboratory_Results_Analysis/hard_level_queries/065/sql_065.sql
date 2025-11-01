WITH cohort_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND d.seq_num = 1
    AND (
      LOWER(di.long_title) LIKE '%gastrointestinal hemorrhage%'
      OR LOWER(di.long_title) LIKE '%lower gastrointestinal bleeding%'
      OR LOWER(di.long_title) LIKE '%hemorrhage of colon%'
      OR LOWER(di.long_title) LIKE '%hemorrhage of rectum%'
      OR LOWER(di.long_title) LIKE '%hemorrhage of anus%'
    )
),

cohort_lab_events AS (
  SELECT
    cp.subject_id,
    COUNT(*) AS critical_lab_count
  FROM
    cohort_patients cp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cp.subject_id = le.subject_id AND cp.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN cp.admittime AND cp.admittime + INTERVAL '72 hour'
    AND le.flag = 'critical'
  GROUP BY
    cp.subject_id
),

cohort_25th_percentile AS (
  SELECT
    PERCENTILE_CONT(critical_lab_count, 0.25) WITHIN GROUP (ORDER BY critical_lab_count) AS lab_instability_25th_percentile
  FROM
    cohort_lab_events
),

general_inpatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),

general_lab_events AS (
  SELECT
    gi.subject_id,
    COUNT(*) AS critical_lab_count
  FROM
    general_inpatients gi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON gi.subject_id = le.subject_id AND gi.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN gi.admittime AND gi.admittime + INTERVAL '72 hour'
    AND le.flag = 'critical'
  GROUP BY
    gi.subject_id
),

general_avg AS (
  SELECT
    AVG(critical_lab_count) AS general_avg_critical_lab
  FROM
    general_lab_events
),

cohort_los_mortality AS (
  SELECT
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate
  FROM
    cohort_patients
)

SELECT
  c25.lab_instability_25th_percentile,
  ga.general_avg_critical_lab,
  clm.avg_los_days,
  clm.mortality_rate
FROM
  cohort_25th_percentile c25,
  general_avg ga,
  cohort_los_mortality clm;