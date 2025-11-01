WITH male_patients_63_73 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 63 AND 73
),

cardiac_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS distinct_cardiac_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    p.subject_id IN (SELECT subject_id FROM male_patients_63_73)
    AND (
      LOWER(d.long_title) LIKE '%cardiac%'
      OR LOWER(d.long_title) LIKE '%heart%'
      OR LOWER(d.long_title) LIKE '%coronary%'
      OR LOWER(d.long_title) LIKE '%aortic%'
      OR LOWER(d.long_title) LIKE '%valve%'
      OR LOWER(d.long_title) LIKE '%bypass%'
      OR LOWER(d.long_title) LIKE '%stent%'
      OR LOWER(d.long_title) LIKE '%angioplasty%'
    )
  GROUP BY
    p.subject_id, p.hadm_id
)

SELECT
  PERCENTILE_CONT(distinct_cardiac_procedures, 0.75) OVER() AS percentile_75
FROM
  cardiac_procedures
LIMIT 1;