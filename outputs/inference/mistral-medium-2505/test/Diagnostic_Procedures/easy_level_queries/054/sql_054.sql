WITH female_81_91 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),

echo_procedures AS (
  SELECT
    h.subject_id,
    COUNT(DISTINCT h.hcpcs_cd) AS distinct_echo_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    female_81_91 f ON h.subject_id = f.subject_id
  WHERE
    h.hcpcs_cd IN (
      '93306', '93307', '93308', '93312', '93313', '93314'
    )
  GROUP BY
    h.subject_id
)

SELECT
  MAX(distinct_echo_count) AS max_distinct_echo_procedures
FROM
  echo_procedures;