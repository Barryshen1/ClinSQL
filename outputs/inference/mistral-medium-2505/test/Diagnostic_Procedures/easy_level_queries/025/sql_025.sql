WITH female_patients_40_50 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),

procedures_per_patient AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedures_count
  FROM
    female_patients_40_50 p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  ON
    p.subject_id = proc.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    proc.icd_code = d.icd_code
    AND proc.icd_version = d.icd_version
  WHERE
    -- Filter for mechanical circulatory support procedures (example: ECMO or IABP)
    -- Note: This is a placeholder; adjust based on actual ICD codes for these procedures
    d.long_title LIKE '%circulatory support%'
    OR d.long_title LIKE '%ECMO%'
    OR d.long_title LIKE '%IABP%'
  GROUP BY
    p.subject_id
)

SELECT
  MIN(distinct_procedures_count) AS min_distinct_procedures_per_patient
FROM
  procedures_per_patient;