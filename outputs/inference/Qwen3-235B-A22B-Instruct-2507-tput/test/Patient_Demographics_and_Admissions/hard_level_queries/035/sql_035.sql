WITH age_at_admission AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admit,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
),

-- Filter for male, age 68-78, Medicare, admitted from SNF
cohort_admissions AS (
  SELECT *
  FROM age_at_admission
  WHERE gender = 'M'
    AND age_at_admit BETWEEN 68 AND 78
    AND insurance = 'Medicare'
    AND LOWER(admission_location) LIKE '%snf%'
    AND LOWER(admission_location) LIKE '%skilled%'
),

-- Get principal diagnosis (seq_num = 1) and join with d_icd_diagnoses
principal_diagnoses AS (
  SELECT
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.seq_num = 1
),

-- Filter for UTI: ICD-9 '5990', ICD-10 'N390'
uti_cohort AS (
  SELECT ca.*
  FROM cohort_admissions ca
  JOIN principal_diagnoses pd ON ca.hadm_id = pd.hadm_id
  WHERE (pd.icd_version = 1 AND pd.icd_code = '5990')   -- ICD-9 UTI
     OR (pd.icd_version = 10 AND pd.icd_code = 'N390')  -- ICD-10 UTI
),

-- Determine index admissions: exclude those that are readmissions (within 30 days of prior)
index_admissions AS (
  SELECT
    *,
    LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_dischtime
  FROM uti_cohort
),

-- Only keep admissions that are NOT within 30 days of prior discharge (i.e., true index)
true_index AS (
  SELECT *
  FROM index_admissions
  WHERE prev_dischtime IS NULL OR admittime > DATETIME_ADD(prev_dischtime, INTERVAL 30 DAY)
),

-- Flag 30-day readmission: next admission within 30 days of discharge
readmission_flagged AS (
  SELECT
    ti.*,
    LEAD(ti.admittime) OVER (PARTITION BY ti.subject_id ORDER BY ti.admittime) AS next_admittime,
    CASE
      WHEN LEAD(ti.admittime) OVER (PARTITION BY ti.subject_id ORDER BY ti.admittime) IS NOT NULL
        AND LEAD(ti.admittime) OVER (PARTITION BY ti.subject_id ORDER BY ti.admittime) <= DATETIME_ADD(ti.dischtime, INTERVAL 30 DAY)
        THEN 1
      ELSE 0
    END AS readmitted_30day
  FROM true_index ti
),

-- Final metrics
summary_stats AS (
  SELECT
    readmitted_30day,
    los_days,
    CASE WHEN los_days > 6 THEN 1 ELSE 0 END AS los_gt_6
  FROM readmission_flagged
)

-- Aggregate results
SELECT
  AVG(CAST(readmitted_30day AS FLOAT64)) AS readmission_rate_30day,
  APPROX_QUANTILES(CASE WHEN readmitted_30day = 1 THEN los_days END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30day = 0 THEN los_days END, 2)[OFFSET(1)] AS median_los_non_readmitted,
  AVG(CAST(los_gt_6 AS FLOAT64)) AS pct_los_gt_6_days
FROM summary_stats;