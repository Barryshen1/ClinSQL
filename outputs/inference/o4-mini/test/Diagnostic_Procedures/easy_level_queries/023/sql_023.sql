WITH cardiac_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
      ON p.icd_code = d.icd_code
      AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%cardi%'
),
hadm_procedure_counts AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT cp.icd_code) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON a.subject_id = pat.subject_id
    LEFT JOIN cardiac_procedures AS cp
      ON a.hadm_id = cp.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 82 AND 92
  GROUP BY
    a.hadm_id
),
quantiles AS (
  SELECT
    APPROX_QUANTILES(procedure_count, 100) AS quantile_array
  FROM
    hadm_procedure_counts
)
SELECT
  quantile_array[OFFSET(25)] AS percentile_25
FROM
  quantiles;