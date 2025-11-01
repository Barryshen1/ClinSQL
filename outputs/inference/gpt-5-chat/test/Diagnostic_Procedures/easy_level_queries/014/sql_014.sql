WITH mcs_devices AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    di.label AS device_label,
    pe.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON a.subject_id = pe.subject_id
   AND a.hadm_id = pe.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    -- Mechanical circulatory support keywords
    AND (
      LOWER(di.label) LIKE '%ecmo%'         -- Extracorporeal Membrane Oxygenation
      OR LOWER(di.label) LIKE '%balloon%'   -- Intra-aortic balloon pump
      OR LOWER(di.label) LIKE '%vad%'       -- Ventricular Assist Device
      OR LOWER(di.label) LIKE '%impella%'   -- Impella device
      OR LOWER(di.label) LIKE '%assist device%' -- generic wording
    )
),
device_count_per_hadm AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT itemid) AS num_devices
  FROM mcs_devices
  GROUP BY hadm_id
)
SELECT
  PERCENTILE_CONT(num_devices, 0.5) OVER() AS median_num_devices
FROM device_count_per_hadm
LIMIT 1;