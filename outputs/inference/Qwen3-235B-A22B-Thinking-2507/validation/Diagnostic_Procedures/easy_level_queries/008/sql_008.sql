WITH patient_echo_counts AS (
  SELECT 
    p.subject_id,
    COUNT(d.code) AS echo_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
    ON p.subject_id = hc.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON hc.hcpcs_cd = d.code
    AND (LOWER(d.long_description) LIKE '%echocardiography%' OR LOWER(d.long_description) LIKE '%echo%')
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 88 AND 98
  GROUP BY p.subject_id
)
SELECT 
  APPROX_QUANTILES(echo_count, 1000)[OFFSET(250)] AS p25
FROM patient_echo_counts;