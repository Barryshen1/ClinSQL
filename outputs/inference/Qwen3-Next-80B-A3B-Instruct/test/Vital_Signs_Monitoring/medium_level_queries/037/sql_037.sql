WITH hfnc_patients AS (
  SELECT DISTINCT i.subject_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON i.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%high%flow%' 
    AND LOWER(di.label) LIKE '%cannula%'
),
gcs_measurements AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS gcs_total,
    ce.charttime,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ce.stay_id = i.stay_id
  WHERE LOWER(di.label) LIKE '%gcs%' 
    AND LOWER(di.label) LIKE '%total%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum >= 3 
    AND ce.valuenum <= 15
),
eligible_patients AS (
  SELECT DISTINCT gcs.stay_id, gcs.gcs_total
  FROM gcs_measurements gcs
  JOIN hfnc_patients hfnc ON gcs.stay_id = hfnc.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON hfnc.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND gcs.charttime >= hfnc.intime + INTERVAL '48 hours'
)
SELECT PERCENTILE_CONT(gcs_total, 0.5) AS median_gcs_total
FROM eligible_patients;