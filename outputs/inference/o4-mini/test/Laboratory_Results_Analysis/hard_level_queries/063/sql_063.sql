WITH pe_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    LOWER(dd.long_title) LIKE '%pulmonary embolism%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
lab_stats AS (
  SELECT
    pe.subject_id,
    pe.hadm_id,
    STDDEV(le.valuenum) AS instability_score_72h,
    SAFE_DIVIDE(
      SUM(IF(le.flag = 'abnormal', 1, 0)),
      COUNT(*) ) AS critical_lab_rate
  FROM
    pe_admissions pe
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON pe.subject_id = le.subject_id
     AND pe.hadm_id    = le.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN pe.admittime
                         AND TIMESTAMP_ADD(pe.admittime, INTERVAL 72 HOUR)
  GROUP BY
    pe.subject_id,
    pe.hadm_id
),
pct75 AS (
  SELECT
    APPROX_QUANTILES(instability_score_72h, 100)[OFFSET(75)] AS threshold_75
  FROM
    lab_stats
),
high_inst AS (
  SELECT
    ls.subject_id,
    ls.hadm_id,
    ls.instability_score_72h,
    ls.critical_lab_rate,
    pa.dischtime,
    pa.admittime,
    pa.hospital_expire_flag
  FROM
    lab_stats ls
    CROSS JOIN pct75
    JOIN pe_admissions pa
      ON ls.subject_id = pa.subject_id
     AND ls.hadm_id    = pa.hadm_id
  WHERE
    ls.instability_score_72h >= pct75.threshold_75
),
high_inst_summary AS (
  SELECT
    100.0 * AVG(hospital_expire_flag)               AS mortality_pct,
    AVG(DATE_DIFF(dischtime, admittime, DAY))       AS mean_los_days,
    AVG(critical_lab_rate)                          AS high_inst_crit_lab_rate
  FROM
    high_inst
),
overall_crit_rate AS (
  SELECT
    AVG(critical_lab_rate) AS overall_crit_lab_rate
  FROM (
    SELECT
      a.hadm_id,
      SAFE_DIVIDE(
        SUM(IF(le.flag = 'abnormal', 1, 0)),
        COUNT(*) ) AS critical_lab_rate
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON a.subject_id = le.subject_id
       AND a.hadm_id    = le.hadm_id
    WHERE
      le.valuenum IS NOT NULL
      AND le.charttime BETWEEN a.admittime
                           AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    GROUP BY
      a.hadm_id
  )
)
SELECT
  hs.mortality_pct,
  hs.mean_los_days,
  hs.high_inst_crit_lab_rate,
  o.overall_crit_lab_rate
FROM
  high_inst_summary hs
  CROSS JOIN overall_crit_rate o;