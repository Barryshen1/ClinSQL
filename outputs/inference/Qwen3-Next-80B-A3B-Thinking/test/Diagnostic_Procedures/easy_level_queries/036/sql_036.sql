WITH valve_procedures AS (
  SELECT
    p.subject_id,
    pi.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON a.hadm_id = pi.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 42 AND 52
    AND d.long_title LIKE '%valve%'
    AND (d.long_title LIKE '%repair%' OR d.long_title LIKE '%replacement%')
)
SELECT
  AVG(num_procedures) AS avg_valve_procedures
FROM (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS num_procedures
  FROM
    valve_procedures
  GROUP BY
    subject_id
);