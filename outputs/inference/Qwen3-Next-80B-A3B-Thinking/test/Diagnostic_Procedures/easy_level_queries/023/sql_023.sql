WITH cardiac_procedures AS (
  SELECT
    a.hadm_id,
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
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      LOWER(d.long_title) LIKE '%cardiac%'
      OR LOWER(d.long_title) LIKE '%heart%'
      OR LOWER(d.long_title) LIKE '%coronary%'
      OR LOWER(d.long_title) LIKE '%myocardial%'
      OR LOWER(d.long_title) LIKE '%valve%'
      OR LOWER(d.long_title) LIKE '%bypass%'
      OR LOWER(d.long_title) LIKE '%angioplasty%'
      OR LOWER(d.long_title) LIKE '%stent%'
      OR LOWER(d.long_title) LIKE '%pacemaker%'
      OR LOWER(d.long_title) LIKE '%defibrillator%'
    )
),
counts_per_hadm AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_cardiac_procedures
  FROM
    cardiac_procedures
  GROUP BY
    hadm_id
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY num_cardiac_procedures) AS percentile_25
FROM
  counts_per_hadm;