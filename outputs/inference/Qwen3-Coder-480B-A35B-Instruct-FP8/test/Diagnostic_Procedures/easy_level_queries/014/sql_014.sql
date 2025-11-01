WITH cohort AS (
  SELECT p.subject_id, p.gender, p.anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),
icu_stays AS (
  SELECT subject_id, hadm_id, stay_id
  FROM physionet-data.mimiciv_3_1_icu.icustays
),
circ_support_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE category = 'Ventilation'
     OR LOWER(label) LIKE '%impella%'
     OR LOWER(label) LIKE '%ecmo%'
     OR LOWER(label) LIKE '%iabp%'
),
device_counts_per_admission AS (
  SELECT
    icu.hadm_id,
    COUNT(DISTINCT pe.itemid) AS distinct_devices
  FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
  JOIN icu_stays icu
    ON pe.stay_id = icu.stay_id
  JOIN cohort c
    ON icu.subject_id = c.subject_id
  JOIN circ_support_items d
    ON pe.itemid = d.itemid
  GROUP BY icu.hadm_id
)
SELECT
  APPROX_QUANTILES(distinct_devices, 2)[OFFSET(1)] AS median_distinct_devices_per_hospitalization
FROM device_counts_per_admission;