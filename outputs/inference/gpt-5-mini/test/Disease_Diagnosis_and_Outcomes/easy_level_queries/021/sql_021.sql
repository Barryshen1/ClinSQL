WITH hadm_dx_flags AS (
  SELECT
    d.hadm_id,
    MAX(
      CASE
        WHEN (
          LOWER(dd.long_title) LIKE '%hemorrhag%' OR
          LOWER(dd.long_title) LIKE '%haemorrhag%' OR
          LOWER(dd.long_title) LIKE '%subarachnoid%' OR
          LOWER(dd.long_title) LIKE '%intracerebral%'
        ) THEN 1 ELSE 0
      END
    ) AS has_hemorrhagic,
    MAX(
      CASE
        WHEN (
          (LOWER(dd.long_title) LIKE '%chronic obstructive%' AND LOWER(dd.long_title) LIKE '%exacerb%')
          OR (LOWER(dd.long_title) LIKE '%copd%' AND LOWER(dd.long_title) LIKE '%exacerb%')
          OR LOWER(dd.long_title) LIKE '%acute exacerbation%'
        ) THEN 1 ELSE 0
      END
    ) AS has_copd_exacerb
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  GROUP BY d.hadm_id
),

cohort_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 1440.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN hadm_dx_flags h
    ON a.hadm_id = h.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND h.has_hemorrhagic = 1
    AND h.has_copd_exacerb = 1
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

quant AS (
  SELECT APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM cohort_admissions
),

counts AS (
  SELECT COUNT(*) AS n_admissions
  FROM cohort_admissions
)

SELECT
  c.n_admissions,
  q.quantiles[OFFSET(1)] AS p25_days,
  q.quantiles[OFFSET(2)] AS median_days,
  q.quantiles[OFFSET(3)] AS p75_days,
  q.quantiles[OFFSET(3)] - q.quantiles[OFFSET(1)] AS iqr_days
FROM counts c
CROSS JOIN quant q;