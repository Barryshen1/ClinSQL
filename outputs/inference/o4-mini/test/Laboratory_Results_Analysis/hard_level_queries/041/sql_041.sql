WITH hf_admissions AS (
  -- 1. Identify male patients aged 54-64 with heart failure, first admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dc
      ON d.icd_code = dc.icd_code
      AND d.icd_version = dc.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND LOWER(dc.long_title) LIKE '%heart failure%'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
lab_48h AS (
  -- 2. All lab events in first 48h
  SELECT
    le.subject_id,
    le.hadm_id,
    le.itemid,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    TIMESTAMP_DIFF(le.charttime, adm.admittime, HOUR) AS hours_since_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN hf_admissions adm
      ON le.hadm_id = adm.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND TIMESTAMP_DIFF(le.charttime, adm.admittime, HOUR) BETWEEN 0 AND 48
),
instability_per_patient AS (
  -- 3. Compute instability score: count distinct abnormal tests
  SELECT
    hadm_id,
    COUNT(DISTINCT IF(
      valuenum < ref_range_lower
      OR valuenum > ref_range_upper,
      itemid,
      NULL
    )) AS instability_score,
    COUNT(1) AS total_labs,
    SUM(IF(
      valuenum < ref_range_lower * 0.5
      OR valuenum > ref_range_upper * 1.5,
      1,
      0
    )) AS critical_labs
  FROM
    lab_48h
  GROUP BY
    hadm_id
),
percentiles AS (
  -- 4. Compute 95th percentile across instability scores
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability
  FROM
    instability_per_patient
),
labeled AS (
  -- 5. Label high vs control
  SELECT
    ip.hadm_id,
    ip.instability_score,
    ip.total_labs,
    ip.critical_labs,
    CASE
      WHEN ip.instability_score >= p.p95_instability THEN 'high_instability'
      ELSE 'control'
    END AS group_label
  FROM
    instability_per_patient ip
    CROSS JOIN percentiles p
),
outcomes AS (
  -- 6. Join back to admissions to get mortality and LOS
  SELECT
    l.group_label,
    COUNT(1) AS n_patients,
    AVG(a.hospital_expire_flag) AS in_hospital_mortality_rate,
    AVG(a.los_days) AS mean_los_days,
    SUM(l.critical_labs) * 1.0 / SUM(l.total_labs) AS critical_lab_rate
  FROM
    labeled l
    JOIN hf_admissions a
      ON l.hadm_id = a.hadm_id
  GROUP BY
    l.group_label
)
-- Final comparison table
SELECT
  group_label,
  n_patients,
  in_hospital_mortality_rate,
  mean_los_days,
  critical_lab_rate
FROM
  outcomes
ORDER BY
  group_label;