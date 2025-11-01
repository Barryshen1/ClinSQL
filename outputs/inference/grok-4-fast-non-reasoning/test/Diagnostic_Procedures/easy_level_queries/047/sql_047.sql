SELECT
  STDDEV(qualified_procedure_count) AS sd_distinct_procedures
FROM (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS qualified_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 37 AND 47
    AND p.icd_version = '9'
    AND p.hadm_id IS NOT NULL
    AND p.icd_code IN ('25.41', '25.42', '25.43', '25.44')
  GROUP BY
    p.hadm_id
  HAVING
    qualified_procedure_count > 0
);