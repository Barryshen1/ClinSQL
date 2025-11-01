WITH procedures_filtered AS (
  SELECT
    p.subject_id,
    p.anchor_year,
    p.anchor_age,
    pi.chartdate,
    d.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pi.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (d.long_title LIKE '%ablation%' OR d.long_title LIKE '%cardioversion%')
    AND (EXTRACT(YEAR FROM pi.chartdate) - (p.anchor_year - p.anchor_age)) BETWEEN 75 AND 85
),
counts AS (
  SELECT
    subject_id,
    COUNT(*) AS procedure_count
  FROM
    procedures_filtered
  GROUP BY
    subject_id
)
SELECT
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] - APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS iqr
FROM
  counts;