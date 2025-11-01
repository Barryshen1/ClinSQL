WITH cardiac_arrest_diagnoses AS (
  SELECT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%cardiac arrest%'
),
female_post_arrest AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN cardiac_arrest_diagnoses ca
      ON a.subject_id = ca.subject_id
     AND a.hadm_id = ca.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
lab_instability AS (
  SELECT
    fpa.hadm_id,
    COUNTIF(
      le.valuenum IS NOT NULL
      AND le.ref_range_lower IS NOT NULL
      AND le.ref_range_upper IS NOT NULL
      AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    ) AS instability_score,
    COUNTIF(
      le.valuenum IS NOT NULL
      AND le.ref_range_lower IS NOT NULL
      AND le.ref_range_upper IS NOT NULL
      AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    ) * 1.0 AS abnormal_lab_count_48h
  FROM
    female_post_arrest fpa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON fpa.hadm_id = le.hadm_id
     AND le.charttime BETWEEN fpa.admittime AND TIMESTAMP_ADD(fpa.admittime, INTERVAL 48 HOUR)
  GROUP BY
    fpa.hadm_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM lab_instability
),
cohort_with_scores AS (
  SELECT
    fpa.*,
    li.instability_score,
    li.abnormal_lab_count_48h,
    pct.p90_score
  FROM
    female_post_arrest fpa
    JOIN lab_instability li USING (hadm_id)
    CROSS JOIN percentiles pct
),
summary AS (
  SELECT
    CASE WHEN instability_score >= p90_score THEN 'high_instability' ELSE 'all' END AS group_label,
    COUNT(*) AS admissions_count,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los_days) AS mean_los_days,
    AVG(abnormal_lab_count_48h) AS mean_abnormal_labs_48h
  FROM
    cohort_with_scores
  GROUP BY
    group_label
)
SELECT
  group_label,
  admissions_count,
  mortality_rate,
  mean_los_days,
  mean_abnormal_labs_48h
FROM
  summary
ORDER BY
  group_label DESC;