WITH stroke_icd_codes AS (
  -- List of ischemic stroke ICD codes (ICD-9 and ICD-10)
  SELECT '433' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '4330', 9 UNION ALL
  SELECT '4331', 9 UNION ALL
  SELECT '4332', 9 UNION ALL
  SELECT '4333', 9 UNION ALL
  SELECT '4338', 9 UNION ALL
  SELECT '4339', 9 UNION ALL
  SELECT '434', 9 UNION ALL
  SELECT '4340', 9 UNION ALL
  SELECT '4341', 9 UNION ALL
  SELECT '4349', 9 UNION ALL
  SELECT '436', 9 UNION ALL
  SELECT 'I63', 10 UNION ALL
  SELECT 'I630', 10 UNION ALL
  SELECT 'I631', 10 UNION ALL
  SELECT 'I632', 10 UNION ALL
  SELECT 'I633', 10 UNION ALL
  SELECT 'I634', 10 UNION ALL
  SELECT 'I635', 10 UNION ALL
  SELECT 'I636', 10 UNION ALL
  SELECT 'I638', 10 UNION ALL
  SELECT 'I639', 10
),
stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN stroke_icd_codes s
        ON d.icd_code LIKE CONCAT(s.icd_code, '%') AND d.icd_version = s.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
),
control_admissions AS (
  -- Age-matched male inpatients without ischemic stroke
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN stroke_icd_codes s
        ON d.icd_code LIKE CONCAT(s.icd_code, '%') AND d.icd_version = s.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
),
lab_instability AS (
  -- For each admission, count abnormal labs in first 72 hours
  SELECT
    la.hadm_id,
    COUNTIF(
      la.valuenum IS NOT NULL
      AND la.ref_range_lower IS NOT NULL
      AND la.ref_range_upper IS NOT NULL
      AND (la.valuenum < la.ref_range_lower OR la.valuenum > la.ref_range_upper)
    ) AS instability_score,
    COUNTIF(
      la.flag = 'abnormal'
      AND TIMESTAMP_DIFF(la.charttime, a.admittime, HOUR) BETWEEN 0 AND 72
    ) AS critical_lab_count,
    COUNTIF(
      TIMESTAMP_DIFF(la.charttime, a.admittime, HOUR) BETWEEN 0 AND 72
    ) AS total_lab_count
  FROM physionet-data.mimiciv_3_1_hosp.labevents la
  JOIN stroke_admissions a
    ON la.hadm_id = a.hadm_id
  WHERE TIMESTAMP_DIFF(la.charttime, a.admittime, HOUR) BETWEEN 0 AND 72
  GROUP BY la.hadm_id
),
lab_instability_controls AS (
  -- For controls
  SELECT
    la.hadm_id,
    COUNTIF(
      la.valuenum IS NOT NULL
      AND la.ref_range_lower IS NOT NULL
      AND la.ref_range_upper IS NOT NULL
      AND (la.valuenum < la.ref_range_lower OR la.valuenum > la.ref_range_upper)
    ) AS instability_score,
    COUNTIF(
      la.flag = 'abnormal'
      AND TIMESTAMP_DIFF(la.charttime, a.admittime, HOUR) BETWEEN 0 AND 72
    ) AS critical_lab_count,
    COUNTIF(
      TIMESTAMP_DIFF(la.charttime, a.admittime, HOUR) BETWEEN 0 AND 72
    ) AS total_lab_count
  FROM physionet-data.mimiciv_3_1_hosp.labevents la
  JOIN control_admissions a
    ON la.hadm_id = a.hadm_id
  WHERE TIMESTAMP_DIFF(la.charttime, a.admittime, HOUR) BETWEEN 0 AND 72
  GROUP BY la.hadm_id
),
percentile_75 AS (
  -- Calculate 75th percentile of instability score in stroke group
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS p75
  FROM lab_instability
),
high_instability_stroke AS (
  -- Admissions with instability score above 75th percentile
  SELECT
    li.hadm_id,
    li.instability_score,
    li.critical_lab_count,
    li.total_lab_count,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days
  FROM lab_instability li
  JOIN stroke_admissions a
    ON li.hadm_id = a.hadm_id
  JOIN percentile_75 p
    ON li.instability_score > p.p75
)
-- Final output
SELECT
  -- 75th percentile value
  (SELECT p75 FROM percentile_75) AS instability_score_75th_percentile,

  -- High-instability stroke group stats
  (SELECT COUNT(*) FROM high_instability_stroke) AS high_instability_stroke_count,
  (SELECT AVG(los_days) FROM high_instability_stroke) AS avg_los_days,
  (SELECT AVG(hospital_expire_flag) FROM high_instability_stroke) AS mortality_rate,
  (SELECT SAFE_DIVIDE(SUM(critical_lab_count), SUM(total_lab_count)) FROM high_instability_stroke) AS critical_lab_rate_high_instability,

  -- Controls stats
  (SELECT SAFE_DIVIDE(SUM(critical_lab_count), SUM(total_lab_count)) FROM lab_instability_controls) AS critical_lab_rate_controls
;