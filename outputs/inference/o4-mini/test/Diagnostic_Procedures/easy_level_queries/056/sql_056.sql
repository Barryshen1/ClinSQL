WITH female_cohort AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),

mech_proc AS (
  SELECT
    p.subject_id,
    p.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
      ON p.icd_code = d.icd_code
      AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%mechanical circulatory support%'
),

proc_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS proc_count
  FROM
    mech_proc
  GROUP BY
    subject_id
),

patient_counts AS (
  -- include zeros for patients with no mechanical support procedures
  SELECT
    fc.subject_id,
    IFNULL(pc.proc_count, 0) AS proc_count
  FROM
    female_cohort AS fc
    LEFT JOIN proc_counts AS pc
      USING (subject_id)
)

SELECT
  APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS pct25_distinct_mech_support
FROM
  patient_counts;