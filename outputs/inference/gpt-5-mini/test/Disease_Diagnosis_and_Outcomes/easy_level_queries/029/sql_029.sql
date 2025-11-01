WITH diag_text AS (
  -- bring in diagnosis descriptions (lowercased for simpler matching)
  SELECT
    d.hadm_id,
    LOWER(dd.long_title) AS long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE dd.long_title IS NOT NULL
),
diag_flags AS (
  -- mark diagnoses that look like UGIB or COPD exacerbation
  SELECT
    hadm_id,
    MAX(
      IF(
        (
          long_title LIKE '%hematemesis%' OR
          long_title LIKE '%melena%' OR
          long_title LIKE '%gastrointestinal hemorrh%' OR
          long_title LIKE '%gastrointestinal haemorrh%' OR
          long_title LIKE '%upper gastrointestinal%' OR
          (
            long_title LIKE '%hemorrh%' AND
            (
              long_title LIKE '%gastro%' OR
              long_title LIKE '%gastric%' OR
              long_title LIKE '%duodenal%' OR
              long_title LIKE '%esophag%' OR
              long_title LIKE '%esophageal%' OR
              long_title LIKE '%variceal%'
            )
          ) OR
          long_title LIKE '%mallory-weiss%'
        ),
        1,
        0
      )
    ) AS has_ugib,
    MAX(
      IF(
        (
          (long_title LIKE '%chronic obstructive%' AND long_title LIKE '%exacerb%') OR
          (long_title LIKE '%copd%' AND long_title LIKE '%exacerb%') OR
          long_title LIKE '%acute exacerbation of copd%' OR
          long_title LIKE '%acute exacerbation%' AND long_title LIKE '%copd%'
        ),
        1,
        0
      )
    ) AS has_copd
  FROM diag_text
  GROUP BY hadm_id
),
cohort AS (
  -- admissions joining patients and requiring both diagnosis flags
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN diag_flags f
    ON a.hadm_id = f.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND f.has_ugib = 1
    AND f.has_copd = 1
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  COUNT(*) AS n_admissions,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM cohort;