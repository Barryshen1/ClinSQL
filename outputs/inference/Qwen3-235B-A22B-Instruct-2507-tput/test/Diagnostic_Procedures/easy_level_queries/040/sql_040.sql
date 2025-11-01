WITH ecg_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE LOWER(short_description) LIKE '%ecg%'
     OR LOWER(short_description) LIKE '%electrocardiogram%'
     OR LOWER(short_description) LIKE '%telemetry%'
     OR LOWER(short_description) LIKE '%cardiac monitor%'
     OR LOWER(long_description) LIKE '%ecg%'
     OR LOWER(long_description) LIKE '%electrocardiogram%'
     OR LOWER(long_description) LIKE '%telemetry%'
     OR LOWER(long_description) LIKE '%cardiac monitor%'
),
patient_ecg_counts AS (
  SELECT
    p.subject_id,
    COUNT(*) AS ecg_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON p.subject_id = h.subject_id
  INNER JOIN ecg_codes e
    ON h.hcpcs_cd = e.code
  WHERE p.gender = 'M'
    AND p.anchor_age >= 51
    AND p.anchor_age <= 61
  GROUP BY p.subject_id
)
SELECT
  PERCENTILE_CONT(ecg_count, 0.25) OVER() AS percentile_25
FROM patient_ecg_counts
LIMIT 1;