WITH echocardiography_procedures AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT h.hcpcs_cd) AS distinct_echo_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON h.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND h.hcpcs_cd IN ('93306', '93307', '93308') -- Common echocardiography HCPCS codes
  GROUP BY
    p.subject_id
)

SELECT
  PERCENTILE_CONT(distinct_echo_procedures, 0.25) OVER() AS percentile_25
FROM
  echocardiography_procedures
LIMIT 1;