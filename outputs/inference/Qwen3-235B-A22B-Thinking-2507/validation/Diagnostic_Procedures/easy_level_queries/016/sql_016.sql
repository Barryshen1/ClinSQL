WITH cohort AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 75 AND 85
),
ecg_telemetry AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.short_description) LIKE '%ecg%' OR
    LOWER(d.long_description) LIKE '%ecg%' OR
    LOWER(d.short_description) LIKE '%electrocardiogram%' OR
    LOWER(d.long_description) LIKE '%electrocardiogram%' OR
    LOWER(d.short_description) LIKE '%telemetry%' OR
    LOWER(d.long_description) LIKE '%telemetry%' OR
    LOWER(d.short_description) LIKE '%cardiac monitor%' OR
    LOWER(d.long_description) LIKE '%cardiac monitor%'
  GROUP BY h.hadm_id
),
counts AS (
  SELECT 
    c.hadm_id,
    COALESCE(e.proc_count, 0) AS proc_count
  FROM cohort c
  LEFT JOIN ecg_telemetry e
    ON c.hadm_id = e.hadm_id
)
SELECT 
  APPROX_QUANTILES(proc_count, 1000)[OFFSET(750)] AS percentile_75
FROM counts;