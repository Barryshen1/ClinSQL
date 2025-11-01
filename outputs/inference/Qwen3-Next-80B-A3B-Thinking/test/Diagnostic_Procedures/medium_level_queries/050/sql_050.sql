WITH tia_patients AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND d_icd.long_title LIKE '%Transient ischemic attack%'
),
imaging_counts AS (
  SELECT hadm_id, COUNT(*) AS imaging_count
  FROM (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d_hc
      ON hc.hcpcs_cd = d_hc.code
    WHERE 
      d_hc.short_description LIKE '%CT%' OR
      d_hc.short_description LIKE '%MRI%' OR
      d_hc.short_description LIKE '%X-ray%' OR
      d_hc.short_description LIKE '%ultrasound%' OR
      d_hc.short_description LIKE '%fluoroscopy%' OR
      d_hc.short_description LIKE '%nuclear medicine%' OR
      d_hc.long_description LIKE '%CT%' OR
      d_hc.long_description LIKE '%MRI%' OR
      d_hc.long_description LIKE '%X-ray%' OR
      d_hc.long_description LIKE '%ultrasound%' OR
      d_hc.long_description LIKE '%fluoroscopy%' OR
      d_hc.long_description LIKE '%nuclear medicine%'
    UNION ALL
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d_items
      ON pe.itemid = d_items.itemid
    WHERE 
      d_items.label LIKE '%CT%' OR
      d_items.label LIKE '%MRI%' OR
      d_items.label LIKE '%X-ray%' OR
      d_items.label LIKE '%ultrasound%' OR
      d_items.label LIKE '%fluoroscopy%' OR
      d_items.label LIKE '%nuclear medicine%'
  ) AS combined_procedures
  GROUP BY hadm_id
),
combined_data AS (
  SELECT 
    t.hadm_id,
    t.los_days,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM tia_patients t
  LEFT JOIN imaging_counts i
    ON t.hadm_id = i.hadm_id
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS stay_group,
  AVG(imaging_count) AS mean_imaging,
  MIN(imaging_count) AS min_imaging,
  MAX(imaging_count) AS max_imaging
FROM combined_data
WHERE los_days BETWEEN 1 AND 7
GROUP BY stay_group;