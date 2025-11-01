WITH primary_dx AS (
  -- admissions where the primary (seq_num=1) diagnosis suggests upper GI bleeding
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE d.seq_num = 1
    AND REGEXP_CONTAINS(
      LOWER(COALESCE(dd.long_title, '')),
      r'(hematemesis|haematemesis|melena|gastrointestinal hemorrhage|gastrointestinal haemorrhage|upper gastrointestinal|upper gi|gastrointestinal bleed|peptic ulcer.*hemorr|peptic ulcer.*bleed|esophageal varices.*bleed|variceal bleeding)'
    )
),

admissions_with_criteria AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- fractional LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN primary_dx pd ON a.hadm_id = pd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.anchor_age = 70
    AND p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
)

SELECT
  -- approximate 75th percentile LOS (days)
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile_days,
  COUNT(*) AS n_admissions_used
FROM admissions_with_criteria;