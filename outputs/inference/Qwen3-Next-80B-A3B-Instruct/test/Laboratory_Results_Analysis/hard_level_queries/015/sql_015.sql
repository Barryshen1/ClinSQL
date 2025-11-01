WITH stroke_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      LOWER(did.long_title) LIKE '%ischemic stroke%'
      OR LOWER(did.long_title) LIKE '%cerebral infarction%'
      OR d.icd_code IN (
        '433', '433.0', '433.1', '433.2', '433.3', '433.8', '433.9',
        '434', '434.0', '434.01', '434.1', '434.11', '434.9', '434.91',
        '436'
      )
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
),

lab_values_72h AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper
  FROM stroke_cohort sc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON sc.hadm_id = le.hadm_id
  WHERE le.charttime >= sc.admittime
    AND le.charttime <= sc.admittime + INTERVAL '72' HOUR
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),

lab_instability AS (
  SELECT
    subject_id,
    hadm_id,
    STDDEV(valuenum) AS lab_instability_score
  FROM lab_values_72h
  GROUP BY subject_id, hadm_id
  HAVING COUNT(valuenum) >= 3
),

percentile_75 AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.75) AS p75_score
  FROM lab_instability
),

grouped_patients AS (
  SELECT
    li.subject_id,
    li.hadm_id,
    li.lab_instability_score,
    DATETIME_DIFF(sc.dischtime, sc.admittime, DAY) AS los_days,
    sc.hospital_expire_flag,
    CASE
      WHEN li.lab_instability_score >= (SELECT p75_score FROM percentile_75) THEN 'high'
      ELSE 'low'
    END AS instability_group
  FROM lab_instability li
  INNER JOIN stroke_cohort sc
    ON li.subject_id = sc.subject_id AND li.hadm_id = sc.hadm_id
),

critical_lab_flags AS (
  SELECT
    lv.subject_id,
    lv.hadm_id,
    MAX(CASE WHEN lv.valuenum < lv.ref_range_lower OR lv.valuenum > lv.ref_range_upper THEN 1 ELSE 0 END) AS has_critical_lab
  FROM lab_values_72h lv
  GROUP BY lv.subject_id, lv.hadm_id
),

final_metrics AS (
  SELECT
    (SELECT p75_score FROM percentile_75) AS p75_score,
    AVG(CASE WHEN gp.instability_group = 'high' THEN gp.los_days END) AS high_los_avg,
    AVG(CASE WHEN gp.instability_group = 'high' THEN gp.hospital_expire_flag END) AS high_mortality_rate,
    AVG(CASE WHEN gp.instability_group = 'high' THEN clf.has_critical_lab END) AS high_critical_lab_rate,
    AVG(CASE WHEN gp.instability_group = 'low' THEN clf.has_critical_lab END) AS low_critical_lab_rate
  FROM grouped_patients gp
  INNER JOIN critical_lab_flags clf
    ON gp.subject_id = clf.subject_id AND gp.hadm_id = clf.hadm_id
)

SELECT *
FROM final_metrics;