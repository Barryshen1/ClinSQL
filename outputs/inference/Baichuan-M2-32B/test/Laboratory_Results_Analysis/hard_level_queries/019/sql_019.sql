WITH ap_cohort AS (
  -- Step 1: Identify AP patients (first admission with AP diagnosis) aged 63-73, male.
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND d.icd_code IN ('K85.0', 'K85.1')  -- ICD-10 codes for acute pancreatitis
    AND d.icd_version = 10  -- ICD-10 version
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
lab_events AS (
  -- Step 2: Get lab events for the cohort in the first 72 hours.
  SELECT 
    a.subject_id,
    a.hadm_id,
    le.labevent_id,
    le.itemid,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    -- Compute critical flag based on reference ranges
    CASE 
      WHEN le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL 
        THEN CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1 ELSE 0 END
      WHEN le.ref_range_lower IS NOT NULL 
        THEN CASE WHEN le.valuenum < le.ref_range_lower THEN 1 ELSE 0 END
      WHEN le.ref_range_upper IS NOT NULL 
        THEN CASE WHEN le.valuenum > le.ref_range_upper THEN 1 ELSE 0 END
      ELSE 0 
    END AS is_critical
  FROM ap_cohort a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 72 HOUR
),
score_per_patient AS (
  -- Compute lab-instability score per patient (0 if no events)
  SELECT 
    a.subject_id,
    a.hadm_id,
    COALESCE(SUM(le.is_critical), 0) AS lab_instability_score
  FROM ap_cohort a
  LEFT JOIN lab_events le 
    ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  GROUP BY a.subject_id, a.hadm_id
),
cohort_with_score AS (
  SELECT 
    a.*,
    s.lab_instability_score
  FROM ap_cohort a
  JOIN score_per_patient s 
    ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
),
p90 AS (
  -- Compute the 90th percentile of the score (approximate for efficiency)
  SELECT 
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(90)] AS p90_score
  FROM cohort_with_score
),
high_instability_subgroup AS (
  -- Select patients with score >= P90
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    lab_instability_score
  FROM cohort_with_score
  WHERE lab_instability_score >= (SELECT p90_score FROM p90)
),
-- Overall stats for the subgroup
overall_stats AS (
  SELECT 
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATEDIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE))) AS mean_los
  FROM high_instability_subgroup
),
-- Per-lab critical rates for the subgroup (only for itemids present in the subgroup)
subgroup_lab_rates AS (
  SELECT 
    le.itemid,
    SUM(le.is_critical) / COUNT(*) AS critical_rate_in_subgroup
  FROM high_instability_subgroup h
  JOIN lab_events le 
    ON h.subject_id = le.subject_id AND h.hadm_id = le.hadm_id
  GROUP BY le.itemid
),
-- For general inpatients: compute critical rates for the same itemids in first 72 hours
general_lab_events AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    le.itemid,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    -- Same critical flag logic
    CASE 
      WHEN le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL 
        THEN CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1 ELSE 0 END
      WHEN le.ref_range_lower IS NOT NULL 
        THEN CASE WHEN le.valuenum < le.ref_range_lower THEN 1 ELSE 0 END
      WHEN le.ref_range_upper IS NOT NULL 
        THEN CASE WHEN le.valuenum > le.ref_range_upper THEN 1 ELSE 0 END
      ELSE 0 
    END AS is_critical
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 72 HOUR
    AND le.itemid IN (SELECT itemid FROM subgroup_lab_rates)  -- Restrict to relevant itemids
),
general_lab_rates AS (
  SELECT 
    itemid,
    SUM(is_critical) / COUNT(*) AS critical_rate_in_general
  FROM general_lab_events
  GROUP BY itemid
),
per_lab_rates AS (
  SELECT 
    s.itemid,
    d.label,
    s.critical_rate_in_subgroup,
    g.critical_rate_in_general
  FROM subgroup_lab_rates s
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
    ON s.itemid = d.itemid
  JOIN general_lab_rates g 
    ON s.itemid = g.itemid
)
-- Output overall stats and per-lab rates in a single table with a type column
SELECT 
  'overall' AS result_type,
  mortality_rate,
  mean_los,
  NULL AS itemid,
  NULL AS label,
  NULL AS critical_rate_in_subgroup,
  NULL AS critical_rate_in_general
FROM overall_stats

UNION ALL

SELECT 
  'per_lab' AS result_type,
  NULL,
  NULL,
  itemid,
  label,
  critical_rate_in_subgroup,
  critical_rate_in_general
FROM per_lab_rates;