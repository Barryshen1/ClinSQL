WITH critical_labs AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
  WHERE
    le.flag = 'critical'
    AND le.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 48 HOUR
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
  GROUP BY le.hadm_id
),
base_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64)) AS age_at_admission,
    p.gender,
    COALESCE(cl.lab_instability_score, 0) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN critical_labs cl
    ON a.hadm_id = cl.hadm_id
  WHERE
    a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
asthma_cohort AS (
  SELECT
    ba.hadm_id,
    ba.age_at_admission,
    ba.gender,
    ba.admittime,
    ba.dischtime,
    ba.hospital_expire_flag,
    TIMESTAMP_DIFF(ba.dischtime, ba.admittime, DAY) AS los_days,
    ba.lab_instability_score
  FROM base_admissions ba
  WHERE
    ba.gender = 'F'
    AND ba.age_at_admission BETWEEN 39 AND 49
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = ba.subject_id
        AND d.hadm_id = ba.hadm_id
        AND d.icd_code = 'J45.901'
        AND d.icd_version = 10
    )
),
all_inpatients_cohort AS (
  SELECT
    ba.hadm_id,
    ba.admittime,
    ba.dischtime,
    ba.hospital_expire_flag,
    TIMESTAMP_DIFF(ba.dischtime, ba.admittime, DAY) AS los_days,
    ba.lab_instability_score
  FROM base_admissions ba
),
asthma_agg AS (
  SELECT
    'asthma' AS cohort,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    SUM(hospital_expire_flag) / COUNT(*) AS inhosp_mortality,
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS lab_instability_75th,
    AVG(lab_instability_score) AS critical_labs_per_admission
  FROM asthma_cohort
),
all_inpatients_agg AS (
  SELECT
    'all_inpatients' AS cohort,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    SUM(hospital_expire_flag) / COUNT(*) AS inhosp_mortality,
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS lab_instability_75th,
    AVG(lab_instability_score) AS critical_labs_per_admission
  FROM all_inpatients_cohort
)
SELECT * FROM asthma_agg
UNION ALL
SELECT * FROM all_inpatients_agg;