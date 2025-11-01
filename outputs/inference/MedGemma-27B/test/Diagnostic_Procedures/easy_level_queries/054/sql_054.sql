WITH PatientGroup AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 81 AND 91
),
EchocardiographyProcedures AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE
    dip.long_title LIKE '%echocardiography%'
)
SELECT
  MAX(procedure_count) AS max_distinct_echocardiography_procedures
FROM (
  SELECT
    pg.subject_id,
    COUNT(DISTINCT ep.icd_code) AS procedure_count
  FROM
    PatientGroup AS pg
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pg.subject_id = a.subject_id
  JOIN
    EchocardiographyProcedures AS ep
    ON a.hadm_id = ep.hadm_id
  GROUP BY
    pg.subject_id
) AS PatientProcedureCounts;