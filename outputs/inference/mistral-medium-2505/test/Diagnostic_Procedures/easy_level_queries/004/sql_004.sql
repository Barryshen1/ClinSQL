WITH female_patients_41_51 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),

cabg_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    d.long_title AS procedure_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    p.subject_id IN (SELECT subject_id FROM female_patients_41_51)
    AND (
      -- ICD-9 codes for CABG (36.1x)
      (p.icd_version = 9 AND p.icd_code LIKE '36.1%')
      OR
      -- ICD-10 codes for CABG (0210x)
      (p.icd_version = 10 AND p.icd_code LIKE '0210%')
    )
)

SELECT
  STDDEV(distinct_cabg_count) AS stddev_distinct_cabg_per_patient
FROM (
  SELECT
    subject_id,
    COUNT(DISTINCT procedure_name) AS distinct_cabg_count
  FROM
    cabg_procedures
  GROUP BY
    subject_id
);