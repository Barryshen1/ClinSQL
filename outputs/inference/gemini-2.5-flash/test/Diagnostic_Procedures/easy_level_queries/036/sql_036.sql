SELECT
  AVG(distinct_valve_procedures) AS average_distinct_valve_procedures_per_patient
FROM (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_valve_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    ON p.subject_id = pr.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_pr
    ON pr.icd_code = d_pr.icd_code AND pr.icd_version = d_pr.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND d_pr.long_title LIKE '%valve%'
    AND (d_pr.long_title LIKE '%repair%' OR d_pr.long_title LIKE '%replacement%' OR d_pr.long_title LIKE '%valvuloplasty%')
  GROUP BY
    p.subject_id
) AS PatientProcedureCounts;