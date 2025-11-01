WITH female_40_50 AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),
mcs_procedures AS (
  SELECT
    pi.subject_id,
    pi.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    pi.icd_code = d.icd_code
    AND pi.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%ventricular assist device%'
    OR LOWER(d.long_title) LIKE '%extracorporeal membrane oxygenation%'
    OR LOWER(d.long_title) LIKE '%intra-aortic balloon pump%'
),
patient_mcs_counts AS (
  SELECT
    f.subject_id,
    COUNT(DISTINCT m.icd_code) AS distinct_mcs_count
  FROM
    female_40_50 f
  LEFT JOIN
    mcs_procedures m
  ON
    f.subject_id = m.subject_id
  GROUP BY
    f.subject_id
)
SELECT
  MIN(distinct_mcs_count) AS min_distinct_mcs_procedures_per_patient
FROM
  patient_mcs_counts;