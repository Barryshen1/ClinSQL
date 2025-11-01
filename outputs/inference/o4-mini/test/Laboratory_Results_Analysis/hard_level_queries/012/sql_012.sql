WITH ami_diagnoses AS (
  SELECT
    DISTINCT d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
      ON d.icd_code = di.icd_code
      AND d.icd_version = di.icd_version
  WHERE
    LOWER(di.long_title) LIKE '%acute myocardial infarction%'
),

ami_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN ami_diagnoses adm_diag
      ON a.subject_id = adm_diag.subject_id
      AND a.hadm_id    = adm_diag.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),

general_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),

lab_scores_ami AS (
  SELECT
    ac.subject_id,
    ac.hadm_id,
    -- count of abnormal labs in first 72h
    COUNTIF(le.flag IS NOT NULL AND le.flag <> '') AS lab_instability_score
  FROM ami_cohort ac
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ac.subject_id = le.subject_id
    AND ac.hadm_id    = le.hadm_id
    AND le.charttime BETWEEN ac.admittime
      AND TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR)
  GROUP BY
    ac.subject_id,
    ac.hadm_id
),

lab_scores_general AS (
  SELECT
    gc.subject_id,
    gc.hadm_id,
    COUNTIF(le.flag IS NOT NULL AND le.flag <> '') AS lab_instability_score
  FROM general_cohort gc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON gc.subject_id = le.subject_id
    AND gc.hadm_id    = le.hadm_id
    AND le.charttime BETWEEN gc.admittime
      AND TIMESTAMP_ADD(gc.admittime, INTERVAL 72 HOUR)
  GROUP BY
    gc.subject_id,
    gc.hadm_id
),

ami_summary AS (
  SELECT
    -- 75th percentile
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS p75_instability_score,
    ROUND(AVG(lab_instability_score), 2) AS avg_instability_score,
    COUNT(*) AS n_ami,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)), 2) AS avg_hosp_LOS_days,
    ROUND(AVG(hospital_expire_flag), 3) AS mortality_rate
  FROM
    lab_scores_ami ls
    JOIN ami_cohort ac
      ON ls.subject_id = ac.subject_id
      AND ls.hadm_id    = ac.hadm_id
),

general_summary AS (
  SELECT
    ROUND(AVG(lab_instability_score), 2) AS avg_instability_score_general,
    COUNT(*) AS n_general
  FROM lab_scores_general
)

SELECT
  a.p75_instability_score        AS ami_p75_instability_score,
  a.avg_instability_score        AS ami_avg_instability_score,
  g.avg_instability_score_general AS general_avg_instability_score,
  a.avg_hosp_LOS_days            AS ami_avg_LOS_days,
  a.mortality_rate               AS ami_mortality_rate,
  a.n_ami,
  g.n_general
FROM
  ami_summary a
  CROSS JOIN general_summary g;