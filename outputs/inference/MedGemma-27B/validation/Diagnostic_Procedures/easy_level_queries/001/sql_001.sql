WITH CardiacProcedures AS (
  SELECT
    pr.hadm_id,
    pr.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
    ON pr.icd_code = dip.icd_code AND pr.icd_version = dip.icd_version
  WHERE
    pr.icd_version = '9'
    AND dip.long_title LIKE '%heart%' -- More robust than just '33%'
    AND pr.seq_num = 1 -- Often the primary procedure
)
SELECT
  PERCENTILE_CONT(0.75, distinct_procedures) AS percentile_75
FROM (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT cp.icd_code) AS distinct_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    CardiacProcedures AS cp
    ON a.hadm_id = cp.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
  GROUP BY
    a.hadm_id
) AS procedure_counts;