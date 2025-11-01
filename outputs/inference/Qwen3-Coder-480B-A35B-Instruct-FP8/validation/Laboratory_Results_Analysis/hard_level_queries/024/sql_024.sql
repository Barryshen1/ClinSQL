WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los_days
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
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND d.icd_code IN ('I469', 'I460', 'I461', 'I462', 'I463', 'I468', 'I469') -- cardiac arrest
),

lab_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(*) AS instability_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    c.hadm_id = le.hadm_id
  WHERE
    le.charttime >= c.icu_intime
    AND le.charttime <= DATETIME_ADD(c.icu_intime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
    AND le.valuenum IS NOT NULL
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),

percentile_90 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS score_threshold
  FROM
    lab_scores
),

high_instability AS (
  SELECT
    ls.*,
    c.hospital_expire_flag,
    c.hosp_los_days
  FROM
    lab_scores ls
  JOIN
    cohort c
  ON
    ls.hadm_id = c.hadm_id
  CROSS JOIN
    percentile_90 p90
  WHERE
    ls.instability_score >= p90.score_threshold
),

critical_labs_high AS (
  SELECT
    COUNT(*) AS critical_count
  FROM
    high_instability hi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    hi.hadm_id = le.hadm_id
  WHERE
    le.charttime >= (SELECT MIN(icu_intime) FROM cohort)
    AND le.charttime <= DATETIME_ADD((SELECT MIN(icu_intime) FROM cohort), INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
),

all_critical_labs AS (
  SELECT
    COUNT(*) AS total_critical_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    le.hadm_id = i.hadm_id
  WHERE
    le.charttime >= i.intime
    AND le.charttime <= DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
)

SELECT
  COUNT(*) AS patient_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(hosp_los_days) AS mean_los_days,
  (SELECT critical_count FROM critical_labs_high) AS critical_labs_in_high_group,
  (SELECT total_critical_count FROM all_critical_labs) AS critical_labs_all_inpatients
FROM
  high_instability;