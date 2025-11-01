WITH patients_age AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
),
cohort_ap AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_ADD(a.admittime, INTERVAL 72 HOUR) AS t_72h
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_age p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag 
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE (d_diag.long_title LIKE '%acute pancreatitis%' OR d_diag.icd_code LIKE 'K85%') 
    AND d_diag.icd_version = 10
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
),
general_inpatients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_ADD(a.admittime, INTERVAL 72 HOUR) AS t_72h
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_age p ON a.subject_id = p.subject_id
  WHERE (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
),
lab_abnormal_72h_ap AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS abnormal_count
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN cohort_ap ap ON le.hadm_id = ap.hadm_id
  WHERE le.charttime >= ap.admittime AND le.charttime <= ap.t_72h
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL 
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY le.hadm_id
),
lab_abnormal_72h_general AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS abnormal_count
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN general_inpatients g ON le.hadm_id = g.hadm_id
  WHERE le.charttime >= g.admittime AND le.charttime <= g.t_72h
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL 
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY le.hadm_id
),
p90_score AS (
  SELECT
    APPROX_QUANTILES(abnormal_count, 1000)[OFFSET(900)] AS p90_value
  FROM lab_abnormal_72h_ap
),
ap_above_p90 AS (
  SELECT
    ap.hadm_id,
    ap.hospital_expire_flag,
    ap.dischtime,
    ap.admittime,
    lab.abnormal_count
  FROM cohort_ap ap
  INNER JOIN lab_abnormal_72h_ap lab ON ap.hadm_id = lab.hadm_id
  CROSS JOIN p90_score
  WHERE lab.abnormal_count >= p90_score.p90_value
),
ap_p90_stats AS (
  SELECT
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(abnormal_count) AS mean_abnormal_labs
  FROM ap_above_p90
),
general_stats AS (
  SELECT
    AVG(CAST(g.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(g.dischtime, g.admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(COALESCE(lab.abnormal_count, 0)) AS mean_abnormal_labs
  FROM general_inpatients g
  LEFT JOIN lab_abnormal_72h_general lab ON g.hadm_id = lab.hadm_id
)
SELECT
  'AP >= P90' AS cohort,
  mortality_rate,
  mean_los_days,
  mean_abnormal_labs
FROM ap_p90_stats
UNION ALL
SELECT
  'General Inpatients' AS cohort,
  mortality_rate,
  mean_los_days,
  mean_abnormal_labs
FROM general_stats;