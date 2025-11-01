WITH patient_admissions AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 73 AND 83
),
device_usage AS (
  SELECT pa.hadm_id, COUNT(DISTINCT pe.itemid) as num_devices
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON pa.hadm_id = pe.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ecmo%' OR LOWER(di.label) LIKE '%intra%aortic%balloon%' OR LOWER(di.label) LIKE '%lvad%' OR LOWER(di.label) LIKE '%rvad%'
  GROUP BY pa.hadm_id
)
SELECT APPROX_QUANTILES(num_devices, 100)[OFFSET(50)] AS median_devices
FROM device_usage;