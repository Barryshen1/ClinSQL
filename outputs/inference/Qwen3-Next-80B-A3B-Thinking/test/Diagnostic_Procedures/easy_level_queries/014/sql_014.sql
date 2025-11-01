WITH target_hadm AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),

icu_devices AS (
  SELECT
    pe.hadm_id,
    di.label AS device_name
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE pe.hadm_id IN (SELECT hadm_id FROM target_hadm)
    AND (
      LOWER(di.label) LIKE '%ecmo%'
      OR LOWER(di.label) LIKE '%iabp%'
      OR LOWER(di.label) LIKE '%lvad%'
      OR LOWER(di.label) LIKE '%vad%'
      OR LOWER(di.label) LIKE '%circulatory support%'
      OR LOWER(di.label) LIKE '%assist device%'
      OR LOWER(di.label) LIKE '%mechanical circulatory support%'
    )
),

hosp_devices AS (
  SELECT
    pi.hadm_id,
    dip.long_title AS device_name
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE pi.hadm_id IN (SELECT hadm_id FROM target_hadm)
    AND (
      LOWER(dip.long_title) LIKE '%ecmo%'
      OR LOWER(dip.long_title) LIKE '%iabp%'
      OR LOWER(dip.long_title) LIKE '%lvad%'
      OR LOWER(dip.long_title) LIKE '%vad%'
      OR LOWER(dip.long_title) LIKE '%circulatory support%'
      OR LOWER(dip.long_title) LIKE '%assist device%'
      OR LOWER(dip.long_title) LIKE '%mechanical circulatory support%'
    )
),

all_devices AS (
  SELECT hadm_id, device_name FROM icu_devices
  UNION ALL
  SELECT hadm_id, device_name FROM hosp_devices
),

device_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT device_name) AS num_devices
  FROM all_devices
  GROUP BY hadm_id
)

SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY num_devices) AS median_num_devices
FROM device_counts;