WITH patient_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 84 AND 94
),
echo_events AS (
  SELECT 
    h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.long_description) LIKE '%echocardiogram%'
    OR LOWER(d.long_description) LIKE '%echocardiography%'
),
echo_counts AS (
  SELECT 
    pa.hadm_id, 
    COUNT(he.hadm_id) AS echo_count
  FROM patient_admissions pa
  LEFT JOIN echo_events he
    ON pa.hadm_id = he.hadm_id
  GROUP BY pa.hadm_id
)
SELECT 
  APPROX_QUANTILES(echo_count, 100)[OFFSET(25)] AS percentile_25
FROM echo_counts;