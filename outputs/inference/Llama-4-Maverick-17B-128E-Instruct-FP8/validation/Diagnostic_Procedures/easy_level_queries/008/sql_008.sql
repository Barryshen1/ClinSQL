WITH patient_info AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 88 AND 98
),
echo_procedures AS (
  SELECT h.subject_id, COUNT(DISTINCT h.hcpcs_cd) as num_echo_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE h.hcpcs_cd IN (
    '93303', '93304', '93306', '93307', '93308', '93312', '93313', '93314', '93315', '93316', '93317', '93318', '93320', '93321', '93325', '93350', '93351', '93352'
  )
  GROUP BY h.subject_id
)
SELECT APPROX_QUANTILES(ep.num_echo_procedures, 100)[OFFSET(25)] AS percentile_25
FROM patient_info pi
LEFT JOIN echo_procedures ep ON pi.subject_id = ep.subject_id;