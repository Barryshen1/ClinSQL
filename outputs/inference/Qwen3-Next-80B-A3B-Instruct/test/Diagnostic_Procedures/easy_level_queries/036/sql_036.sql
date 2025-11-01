WITH valve_procedures AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pi.icd_code) AS distinct_valve_procedures
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON p.subject_id = pi.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(dip.long_title) LIKE '%valve%'
    AND (LOWER(dip.long_title) LIKE '%repair%' OR LOWER(dip.long_title) LIKE '%replacement%')
  GROUP BY
    p.subject_id
)
SELECT
  AVG(distinct_valve_procedures) AS average_distinct_valve_procedures_per_patient
FROM
  valve_procedures;