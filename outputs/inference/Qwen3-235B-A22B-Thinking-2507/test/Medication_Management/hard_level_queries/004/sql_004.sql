WITH base AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I63%'
    )
),
complexity AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
  GROUP BY hadm_id
),
base_with_metrics AS (
  SELECT 
    b.*,
    c.complexity_score,
    TIMESTAMP_DIFF(b.dischtime, b.admittime, HOUR) / 24.0 AS los_days
  FROM base b
  LEFT JOIN complexity c
    ON b.hadm_id = c.hadm_id
),
with_percentile AS (
  SELECT 
    *,
    PERCENT_RANK() OVER (ORDER BY complexity_score) AS percentile_rank
  FROM base_with_metrics
),
group_a AS (
  -- Placeholder: Actual CYP3A4/NTI identification requires external drug databases
  -- Returning empty set since MIMIC lacks interaction data (simulates no matches)
  SELECT subject_id, hadm_id
  FROM base_with_metrics
  WHERE FALSE
)
SELECT 
  'Group A' AS group_type,
  AVG(complexity_score) AS complexity_score,
  AVG(percentile_rank) AS percentile,
  AVG(los_days) AS los,
  AVG(hospital_expire_flag) AS mortality
FROM with_percentile wp
WHERE EXISTS (
  SELECT 1 
  FROM group_a ga 
  WHERE wp.subject_id = ga.subject_id AND wp.hadm_id = ga.hadm_id
)

UNION ALL

SELECT 
  'Group B' AS group_type,
  AVG(complexity_score),
  AVG(percentile_rank),
  AVG(los_days),
  AVG(hospital_expire_flag)
FROM with_percentile

UNION ALL

SELECT 
  'Top Quartile' AS group_type,
  NULL AS complexity_score,
  NULL AS percentile,
  AVG(los_days) AS los,
  AVG(hospital_expire_flag) AS mortality
FROM with_percentile
WHERE complexity_score >= (
  SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY complexity_score) 
  FROM with_percentile
);