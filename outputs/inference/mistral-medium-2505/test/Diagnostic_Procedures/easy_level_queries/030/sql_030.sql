WITH
-- Get female patients aged 84-94 at admission
female_patients_84_94 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission (approximate)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 84 AND 94
),

-- Identify echocardiography procedures (example HCPCS codes)
echocardiography_procedures AS (
  SELECT DISTINCT
    h.hadm_id,
    h.hcpcs_cd
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON
    h.hcpcs_cd = d.code
  WHERE
    -- Example echocardiography HCPCS codes (adjust as needed)
    h.hcpcs_cd IN ('93306', '93307', '93308', '93312', '93318', '93320', '93321', '93325')
),

-- Count distinct echocardiography procedures per hospitalization
echocardiography_counts AS (
  SELECT
    fp.hadm_id,
    COUNT(DISTINCT ep.hcpcs_cd) AS num_echocardiography_procedures
  FROM
    female_patients_84_94 fp
  LEFT JOIN
    echocardiography_procedures ep
  ON
    fp.hadm_id = ep.hadm_id
  GROUP BY
    fp.hadm_id
)

-- Calculate the 25th percentile
SELECT
  PERCENTILE_CONT(ec.num_echocardiography_procedures, 0.25) OVER() AS percentile_25
FROM
  echocardiography_counts ec
LIMIT 1;