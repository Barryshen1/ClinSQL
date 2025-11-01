WITH base_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admit_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 54 AND 64
),
hf_flags AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    1 AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE ( (d.icd_version = 9  AND SUBSTR(d.icd_code,1,3) = '428')
       OR (d.icd_version = 10 AND UPPER(SUBSTR(d.icd_code,1,3)) = 'I50') )
),
cohort AS (
  SELECT
    b.*,
    COALESCE(hf.has_hf,0) AS has_hf
  FROM base_admissions b
  LEFT JOIN hf_flags hf
    ON b.subject_id = hf.subject_id
    AND b.hadm_id = hf.hadm_id
),
lab_48h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNTIF(flag IS NOT NULL AND LOWER(flag) LIKE '%abnormal%') AS abnormal_lab_count,
    COUNT(*) AS total_labs,
    SAFE_DIVIDE(
      COUNTIF(flag IS NOT NULL AND LOWER(flag) LIKE '%abnormal%'),
      COUNT(*)
    ) AS abnormal_rate
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_labs AS (
  SELECT
    c.*,
    l.abnormal_lab_count,
    l.total_labs,
    l.abnormal_rate
  FROM cohort c
  LEFT JOIN lab_48h l
    ON c.subject_id = l.subject_id
    AND c.hadm_id = l.hadm_id
),
hf_only AS (
  SELECT *
  FROM cohort_with_labs
  WHERE has_hf = 1
),
hf_threshold AS (
  SELECT
    APPROX_QUANTILES(abnormal_lab_count, 100)[OFFSET(95)] AS p95_abn_count
  FROM hf_only
),
hf_high_instab AS (
  SELECT h.*, t.p95_abn_count
  FROM hf_only h
  CROSS JOIN hf_threshold t
  WHERE h.abnormal_lab_count >= t.p95_abn_count
),
hf_high_instab_summary AS (
  SELECT
    COUNT(*) AS n_patients,
    AVG(hospital_expire_flag) AS in_hosp_mortality_rate,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS mean_los_days,
    AVG(abnormal_rate) AS mean_abnormal_rate
  FROM hf_high_instab
),
controls AS (
  SELECT *
  FROM cohort_with_labs
  WHERE has_hf = 0
),
control_stats AS (
  SELECT
    AVG(abnormal_rate) AS mean_abnormal_rate_controls
  FROM controls
)
SELECT
  s.n_patients,
  s.in_hosp_mortality_rate,
  s.mean_los_days,
  s.mean_abnormal_rate AS mean_abn_rate_hf_high_instab,
  c.mean_abnormal_rate_controls
FROM hf_high_instab_summary s
CROSS JOIN control_stats c;