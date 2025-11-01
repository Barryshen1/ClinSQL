WITH target_admissions AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 73 AND 83
),
device_procedures_raw AS (
  SELECT 
    pe.hadm_id,
    CASE
      WHEN LOWER(d.label) LIKE '%ecmo%' OR LOWER(d.label) LIKE '%extracorporeal membrane oxygenation%' THEN 'ECMO'
      WHEN LOWER(d.label) LIKE '%iabp%' OR LOWER(d.label) LIKE '%intra-aortic balloon pump%' THEN 'IABP'
      WHEN LOWER(d.label) LIKE '%vad%' OR LOWER(d.label) LIKE '%ventricular assist device%' THEN 'VAD'
      ELSE NULL
    END AS device_type
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON pe.itemid = d.itemid
  INNER JOIN target_admissions ta 
    ON pe.hadm_id = ta.hadm_id
),
device_procedures AS (
  SELECT 
    hadm_id,
    device_type
  FROM device_procedures_raw
  WHERE device_type IS NOT NULL
),
device_counts AS (
  SELECT 
    ta.hadm_id,
    COUNT(DISTINCT dp.device_type) AS num_devices
  FROM target_admissions ta
  LEFT JOIN device_procedures dp 
    ON ta.hadm_id = dp.hadm_id
  GROUP BY ta.hadm_id
)
SELECT 
  APPROX_QUANTILES(num_devices, 100)[OFFSET(50)] AS median_num_devices
FROM device_counts;