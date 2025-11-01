WITH patient_procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pi.icd_code) AS num_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON p.subject_id = pi.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      LOWER(dip.long_title) LIKE '%pacemaker%'
      OR LOWER(dip.long_title) LIKE '%icd%'
      OR LOWER(dip.long_title) LIKE '%defibrillator%'
      OR LOWER(dip.long_title) LIKE '%cardioverter%'
    )
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(num_procedures, 0.25) OVER () AS percentile_25
FROM
  patient_procedure_counts
LIMIT 1;