SELECT
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(25)] AS percentile_25th
FROM (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON
    p.subject_id = pr.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(d.long_title) LIKE '%echocardiogram%'
  GROUP BY
    p.subject_id
);