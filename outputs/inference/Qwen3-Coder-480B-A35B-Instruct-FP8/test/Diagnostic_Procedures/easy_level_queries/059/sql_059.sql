WITH cardiac_procedures_per_admission AS (
  SELECT
    p.subject_id,
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  ON
    p.subject_id = proc.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
  ON
    proc.icd_code = d_proc.icd_code
    AND proc.icd_version = d_proc.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(d_proc.long_title) LIKE '%cardiac%'
  GROUP BY
    p.subject_id, proc.hadm_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(distinct_procedure_count, 4) AS quantiles
  FROM
    cardiac_procedures_per_admission
)
SELECT
  quantiles[ORDINAL(3)] - quantiles[ORDINAL(1)] AS IQR
FROM
  percentiles;