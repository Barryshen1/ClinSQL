WITH first_admissions AS (
  -- pick all admissions for eligible patients (we'll pick the earliest per subject next)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
),
first_adm_unique AS (
  SELECT
    fa.*
  FROM (
    SELECT
      fa.*,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC, hadm_id ASC) AS rn
    FROM first_admissions fa
  ) fa
  WHERE rn = 1
    AND fa.dischtime IS NOT NULL
    AND fa.admittime IS NOT NULL
    AND TIMESTAMP_DIFF(fa.dischtime, fa.admittime, SECOND) > 0
),
hf_first_adm AS (
  -- keep only first admissions that have a heart failure diagnosis for that admission
  SELECT DISTINCT f.*
  FROM first_adm_unique f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON d.subject_id = f.subject_id
   AND d.hadm_id = f.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON dicd.icd_code = d.icd_code
   AND dicd.icd_version = d.icd_version
  WHERE
    (
      (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '428'))
      OR
      (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I50'))
      OR
      (LOWER(COALESCE(dicd.long_title, '')) LIKE '%heart failure%')
    )
)
SELECT
  stats.n_patients,
  stats.quantiles[OFFSET(25)] AS q1_days,
  stats.quantiles[OFFSET(75)] AS q3_days,
  stats.quantiles[OFFSET(75)] - stats.quantiles[OFFSET(25)] AS iqr_days
FROM (
  SELECT
    COUNT(*) AS n_patients,
    APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM hf_first_adm
) AS stats;