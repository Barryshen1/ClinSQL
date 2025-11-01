WITH device_procs AS (
  SELECT DISTINCT
    pe.hadm_id,
    pe.itemid
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON pe.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON pe.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND LOWER(di.label) LIKE '%iabp%'
     OR LOWER(di.label) LIKE '%ecmo%'
     OR LOWER(di.label) LIKE '%impella%'
     OR LOWER(di.label) LIKE '%vad%'
     OR LOWER(di.label) LIKE '%ventricular assist%'
),
hosp_device_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT itemid) AS device_count
  FROM device_procs
  GROUP BY hadm_id
)
SELECT
  APPROX_QUANTILES(device_count, 100)[OFFSET(50)] AS median_devices_per_hospitalization
FROM hosp_device_counts;