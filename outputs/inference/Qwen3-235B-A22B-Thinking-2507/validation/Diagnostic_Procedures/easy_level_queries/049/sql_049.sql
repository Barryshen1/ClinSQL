WITH target_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 81 AND 91
),
ecg_procedures AS (
  SELECT 
    ta.subject_id,
    h.hcpcs_cd
  FROM target_admissions ta
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON ta.hadm_id = h.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
    AND (
      LOWER(d.long_description) LIKE '%ecg%' OR
      LOWER(d.long_description) LIKE '%ekg%' OR
      LOWER(d.long_description) LIKE '%electrocardiogram%' OR
      LOWER(d.long_description) LIKE '%telemetry%' OR
      LOWER(d.long_description) LIKE '%cardiac monitor%'
    )
),
patient_ecg_counts AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT hcpcs_cd) AS ecg_count
  FROM ecg_procedures
  GROUP BY subject_id
)
SELECT 
  STDDEV_SAMP(ecg_count) AS sd_ecg_count
FROM patient_ecg_counts;