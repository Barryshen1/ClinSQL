WITH asthma_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(dd.long_title) LIKE '%asthma%'
),
control_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%asthma%'
    )
),
lab_events_scored AS (
  SELECT
    adm.hadm_id,
    COUNT(*) AS instability_score
  FROM
    asthma_adm adm
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON adm.subject_id = le.subject_id
      AND adm.hadm_id = le.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    AND le.charttime BETWEEN adm.admittime
      AND TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
  GROUP BY
    adm.hadm_id
),
lab_events_scored_ctrl AS (
  SELECT
    adm.hadm_id,
    COUNT(*) AS instability_score
  FROM
    control_adm adm
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON adm.subject_id = le.subject_id
      AND adm.hadm_id = le.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    AND le.charttime BETWEEN adm.admittime
      AND TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
  GROUP BY
    adm.hadm_id
),
percentiles AS (
  SELECT
    a.asthma_p90,
    c.ctrl_p90
  FROM
    (
      SELECT
        APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS asthma_p90
      FROM lab_events_scored
    ) AS a
  CROSS JOIN
    (
      SELECT
        APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS ctrl_p90
      FROM lab_events_scored_ctrl
    ) AS c
),
asthma_top_decile AS (
  SELECT
    a.*,
    s.instability_score
  FROM
    asthma_adm a
    JOIN lab_events_scored s USING (hadm_id)
    CROSS JOIN percentiles
  WHERE
    s.instability_score >= percentiles.asthma_p90
),
control_top_decile AS (
  SELECT
    a.*,
    s.instability_score
  FROM
    control_adm a
    JOIN lab_events_scored_ctrl s USING (hadm_id)
    CROSS JOIN percentiles
  WHERE
    s.instability_score >= percentiles.ctrl_p90
),
metrics AS (
  SELECT
    'Asthma Top Decile' AS cohort,
    COUNT(*) AS n_patients,
    ROUND(AVG(hospital_expire_flag), 3) AS mortality_rate,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)), 2) AS mean_los_days,
    ROUND(AVG(instability_score), 1) AS avg_crit_lab_events
  FROM asthma_top_decile
  UNION ALL
  SELECT
    'Control Top Decile' AS cohort,
    COUNT(*) AS n_patients,
    ROUND(AVG(hospital_expire_flag), 3) AS mortality_rate,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)), 2) AS mean_los_days,
    ROUND(AVG(instability_score), 1) AS avg_crit_lab_events
  FROM control_top_decile
)
SELECT * FROM metrics;