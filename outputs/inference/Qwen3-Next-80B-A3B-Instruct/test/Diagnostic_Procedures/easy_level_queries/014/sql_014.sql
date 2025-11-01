WITH eligible_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 73 AND 83
),
mechanical_circulatory_devices AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%iabp%'
     OR LOWER(label) LIKE '%ecmo%'
     OR LOWER(label) LIKE '%lvad%'
     OR LOWER(label) LIKE '%vad%'
     OR LOWER(label) LIKE '%tah%'
     OR LOWER(label) LIKE '%mechanical circulatory support%'
),
device_counts_per_hadm AS (
  SELECT 
    ie.hadm_id,
    COUNT(DISTINCT ie.itemid) AS num_distinct_devices
  FROM physionet-data.mimiciv_3_1_icu.procedureevents ie
  INNER JOIN eligible_patients ep ON ie.subject_id = ep.subject_id
  INNER JOIN mechanical_circulatory_devices mcd ON ie.itemid = mcd.itemid
  GROUP BY ie.hadm_id
)
SELECT 
  APPROX_QUANTILES(num_distinct_devices, 1)[OFFSET(0)] AS median_distinct_devices
FROM device_counts_per_hadm;