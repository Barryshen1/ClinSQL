WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE (UPPER(p.gender) = 'F' OR UPPER(p.gender) = 'FEMALE')
    AND p.anchor_age BETWEEN 63 AND 73
),
rr_items AS (
  SELECT di.itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items` di
  WHERE LOWER(di.label) LIKE '%respirat%' OR LOWER(di.label) LIKE '%respiratory rate%'
),
rr_events AS (
  SELECT ce.subject_id,
         CAST(ce.valuenum AS FLOAT64) AS rr_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN rr_items ri ON ce.itemid = ri.itemid
  WHERE ce.valuenum IS NOT NULL
),
per_patient_max AS (
  SELECT rp.subject_id,
         MAX(rp.rr_value) AS max_rr
  FROM rr_events rp
  JOIN target_patients tp ON rp.subject_id = tp.subject_id
  GROUP BY rp.subject_id
)
SELECT STDDEV_SAMP(max_rr) AS sd_max_respiratory_rate
FROM per_patient_max;