WITH asthma_admissions AS (
  -- Identify male admissions aged 52-62 with asthma exacerbation
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` didx
      ON dx.icd_code = didx.icd_code AND dx.icd_version = didx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND (
      LOWER(didx.long_title) LIKE '%asthma%'
      AND LOWER(didx.long_title) LIKE '%exacerbation%'
    )
),
lab_instability AS (
  -- For each admission, count critical lab events in first 72h
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.anchor_age,
    a.gender,
    a.hospital_expire_flag,
    COUNTIF(
      (
        l.valuenum IS NOT NULL
        AND l.ref_range_lower IS NOT NULL
        AND l.ref_range_upper IS NOT NULL
        AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      )
      OR (LOWER(l.flag) = 'abnormal')
    ) AS critical_lab_events
  FROM
    asthma_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
      AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.anchor_age, a.gender, a.hospital_expire_flag
),
percentiles AS (
  -- Calculate 90th percentile for asthma cohort
  SELECT
    APPROX_QUANTILES(critical_lab_events, 10)[9] AS p90_lab_instability
  FROM
    lab_instability
),
top_decile_asthma AS (
  -- Admissions in top decile for asthma cohort
  SELECT
    l.*,
    p.p90_lab_instability
  FROM
    lab_instability l
    CROSS JOIN percentiles p
  WHERE
    l.critical_lab_events >= p.p90_lab_instability
),
asthma_metrics AS (
  -- Metrics for top decile asthma admissions
  SELECT
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS mean_los_days,
    AVG(critical_lab_events) AS avg_critical_lab_events,
    MAX(p90_lab_instability) AS p90_lab_instability
  FROM
    top_decile_asthma
),
age_matched_admissions AS (
  -- All male admissions aged 52-62 (not restricted to asthma)
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
),
lab_instability_age_matched AS (
  -- Lab instability for age-matched males
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.anchor_age,
    a.gender,
    a.hospital_expire_flag,
    COUNTIF(
      (
        l.valuenum IS NOT NULL
        AND l.ref_range_lower IS NOT NULL
        AND l.ref_range_upper IS NOT NULL
        AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      )
      OR (LOWER(l.flag) = 'abnormal')
    ) AS critical_lab_events
  FROM
    age_matched_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
      AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.anchor_age, a.gender, a.hospital_expire_flag
),
percentiles_age_matched AS (
  -- 90th percentile for age-matched males
  SELECT
    APPROX_QUANTILES(critical_lab_events, 10)[9] AS p90_lab_instability
  FROM
    lab_instability_age_matched
),
top_decile_age_matched AS (
  -- Top decile for age-matched males
  SELECT
    l.*,
    p.p90_lab_instability
  FROM
    lab_instability_age_matched l
    CROSS JOIN percentiles_age_matched p
  WHERE
    l.critical_lab_events >= p.p90_lab_instability
),
age_matched_metrics AS (
  -- Metrics for top decile age-matched males
  SELECT
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS mean_los_days,
    AVG(critical_lab_events) AS avg_critical_lab_events,
    MAX(p90_lab_instability) AS p90_lab_instability
  FROM
    top_decile_age_matched
)

-- Final output: metrics for asthma cohort and age-matched males
SELECT
  'Asthma Exacerbation Cohort' AS cohort,
  * 
FROM
  asthma_metrics

UNION ALL

SELECT
  'Age-Matched Males' AS cohort,
  *
FROM
  age_matched_metrics
;