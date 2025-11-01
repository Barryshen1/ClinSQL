WITH ischemic_stroke_codes AS (
  -- List of ICD codes for ischemic stroke (ICD-9 and ICD-10)
  SELECT 'I63' AS icd_prefix, 10 AS icd_version UNION ALL
  SELECT '434' AS icd_prefix, 9 AS icd_version UNION ALL
  SELECT '433' AS icd_prefix, 9 AS icd_version UNION ALL
  SELECT '436' AS icd_prefix, 9 AS icd_version
),
primary_stroke_admissions AS (
  SELECT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN ischemic_stroke_codes isc
      ON di.icd_version = isc.icd_version
      AND (
        -- For ICD-10, match I63.*
        (di.icd_version = 10 AND LEFT(di.icd_code, 3) = isc.icd_prefix)
        -- For ICD-9, match 433.*, 434.*, 436
        OR (di.icd_version = 9 AND LEFT(di.icd_code, LENGTH(isc.icd_prefix)) = isc.icd_prefix)
      )
  WHERE
    di.seq_num = 1 -- principal diagnosis
)
SELECT
  MAX(
    SAFE_CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS INT64)
  ) AS max_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN primary_stroke_admissions psa
    ON a.subject_id = psa.subject_id
    AND a.hadm_id = psa.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 84 AND 94
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;