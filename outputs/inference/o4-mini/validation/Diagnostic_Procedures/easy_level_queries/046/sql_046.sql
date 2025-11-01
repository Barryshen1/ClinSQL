WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
),
mech_support_procs AS (
  SELECT
    pi.hadm_id,
    pi.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
      ON pi.icd_code = dip.icd_code
      AND pi.icd_version = dip.icd_version
  WHERE
    LOWER(dip.long_title) LIKE '%mechanical circulatory support%'
),
proc_counts AS (
  SELECT
    pa.hadm_id,
    COUNT(DISTINCT msp.icd_code) AS distinct_proc_count
  FROM
    patient_admissions AS pa
    LEFT JOIN mech_support_procs AS msp
      ON pa.hadm_id = msp.hadm_id
  GROUP BY
    pa.hadm_id
)
SELECT
  MAX(distinct_proc_count) AS max_distinct_mechanical_support_procedures
FROM
  proc_counts;