WITH cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),
hospitalizations AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort c ON a.subject_id = c.subject_id
),
-- Map ICD codes to device types
mcs_procedures AS (
  SELECT
    pi.hadm_id,
    CASE
      -- Intra-aortic balloon pump
      WHEN (pi.icd_version = 9 AND pi.icd_code = '37.61') OR (pi.icd_version = 10 AND pi.icd_code = '5A02210') THEN 'IABP'
      -- ECMO
      WHEN (pi.icd_version = 9 AND pi.icd_code = '39.65') OR
           (pi.icd_version = 10 AND pi.icd_code IN ('5A15223', '5A15224', '5A1522F')) THEN 'ECMO'
      -- Ventricular assist device
      WHEN (pi.icd_version = 9 AND pi.icd_code = '37.66') OR
           (pi.icd_version = 10 AND pi.icd_code IN ('02HA0QZ', '02HA0RZ', '02HA0SZ', '02HA0TZ')) THEN 'VAD'
      ELSE NULL
    END AS device_type
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN hospitalizations h ON pi.hadm_id = h.hadm_id
  WHERE (
    -- All relevant ICD codes
    (pi.icd_version = 9 AND pi.icd_code IN ('37.61', '39.65', '37.66')) OR
    (pi.icd_version = 10 AND pi.icd_code IN (
      '5A02210', -- IABP
      '5A15223', '5A15224', '5A1522F', -- ECMO
      '02HA0QZ', '02HA0RZ', '02HA0SZ', '02HA0TZ' -- VAD
    ))
  )
),
-- For each hospitalization, count distinct device types
device_counts AS (
  SELECT
    h.hadm_id,
    COUNT(DISTINCT m.device_type) AS n_devices
  FROM hospitalizations h
  LEFT JOIN mcs_procedures m ON h.hadm_id = m.hadm_id
  GROUP BY h.hadm_id
)
-- Compute the median number of distinct devices per hospitalization
SELECT
  APPROX_QUANTILES(n_devices, 2)[OFFSET(1)] AS median_distinct_mcs_devices_per_hospitalization
FROM device_counts;