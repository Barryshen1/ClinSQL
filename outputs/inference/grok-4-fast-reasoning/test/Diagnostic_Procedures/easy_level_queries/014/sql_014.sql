WITH qualifying_hadms AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 73
    AND p.anchor_age <= 83
),
mcs_procedures AS (
  SELECT 
    pi.hadm_id,
    CASE
      WHEN LOWER(dip.long_title) LIKE '%intra-aortic balloon%' 
        OR LOWER(dip.long_title) LIKE '%balloon pump%' 
        THEN 'IABP'
      WHEN LOWER(dip.long_title) LIKE '%ecmo%' 
        OR LOWER(dip.long_title) LIKE '%extracorporeal membrane oxygenation%' 
        THEN 'ECMO'
      WHEN LOWER(dip.long_title) LIKE '%ventricular assist device%' 
        OR LOWER(dip.long_title) LIKE '%heart assist system%' 
        OR LOWER(dip.long_title) LIKE '%heart assist device%' 
        OR LOWER(dip.long_title) LIKE '%mechanical assist device%' 
        OR LOWER(dip.long_title) LIKE '%percutaneous ventricular%' 
        THEN 'VAD'
      ELSE NULL
    END AS device_type
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE (LOWER(dip.long_title) LIKE '%intra-aortic balloon%' 
         OR LOWER(dip.long_title) LIKE '%balloon pump%')
     OR (LOWER(dip.long_title) LIKE '%ecmo%' 
         OR LOWER(dip.long_title) LIKE '%extracorporeal membrane oxygenation%')
     OR (LOWER(dip.long_title) LIKE '%ventricular assist device%' 
         OR LOWER(dip.long_title) LIKE '%heart assist system%' 
         OR LOWER(dip.long_title) LIKE '%heart assist device%' 
         OR LOWER(dip.long_title) LIKE '%mechanical assist device%' 
         OR LOWER(dip.long_title) LIKE '%percutaneous ventricular%')
),
counts_per_hadm AS (
  SELECT 
    q.hadm_id,
    COUNT(DISTINCT m.device_type) AS num_distinct_devices
  FROM qualifying_hadms q
  LEFT JOIN mcs_procedures m
    ON q.hadm_id = m.hadm_id
  GROUP BY q.hadm_id
)
SELECT 
  APPROX_QUANTILES(num_distinct_devices, 2)[OFFSET(1)] AS median_num_devices
FROM counts_per_hadm;