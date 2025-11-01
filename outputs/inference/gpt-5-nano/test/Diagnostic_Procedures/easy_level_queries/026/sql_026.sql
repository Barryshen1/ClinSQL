WITH eligible_pats AS (
  -- Male patients aged 75-85
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),
ablation_codes AS (
  -- ICD procedure records that correspond to ablation or cardioversion
  SELECT DISTINCT p.subject_id, p.hadm_id, p.chartdate, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ablat%' OR LOWER(d.long_title) LIKE '%cardioversion%'
),
counts_per_patient AS (
  -- Distinct procedure events per patient
  SELECT a.subject_id,
         COUNT(DISTINCT CONCAT(CAST(a.hadm_id AS STRING),
                               '|', CAST(a.chartdate AS STRING),
                               '|', a.icd_code)) AS n_procedures
  FROM ablation_codes AS a
  GROUP BY a.subject_id
),
counts_with_zeros AS (
  -- Include patients with zero matching procedures
  SELECT e.subject_id,
         COALESCE(c.n_procedures, 0) AS n_procedures
  FROM eligible_pats e
  LEFT JOIN counts_per_patient c
    ON e.subject_id = c.subject_id
)
SELECT
  CAST(q[OFFSET(25)] AS FLOAT64) AS q1,
  CAST(q[OFFSET(75)] AS FLOAT64) AS q3,
  CAST(q[OFFSET(75)] - q[OFFSET(25)] AS FLOAT64) AS iqr
FROM (
  SELECT APPROX_QUANTILES(n_procedures, 100) AS q
  FROM counts_with_zeros
) t;