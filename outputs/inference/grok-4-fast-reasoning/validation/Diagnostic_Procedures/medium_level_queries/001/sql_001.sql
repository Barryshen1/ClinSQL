WITH acs_diagnoses AS (
  SELECT di.subject_id, di.hadm_id, di.seq_num, di.icd_code, di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%myocardial infarction%' 
     OR LOWER(dd.long_title) LIKE '%unstable angina%'
),
acs_hadms AS (
  SELECT DISTINCT hadm_id
  FROM acs_diagnoses
),
principal_acs AS (
  SELECT DISTINCT hadm_id
  FROM acs_diagnoses
  WHERE seq_num = 1
),
radiology_hcpcs AS (
  SELECT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%ct%' 
     OR LOWER(d.short_description) LIKE '%x-ray%' 
     OR LOWER(d.short_description) LIKE '%radiograph%'
     OR LOWER(d.long_description) LIKE '%ct%' 
     OR LOWER(d.long_description) LIKE '%x-ray%' 
     OR LOWER(d.long_description) LIKE '%radiograph%'
),
imaging_counts AS (
  SELECT hadm_id, COUNT(*) AS img_count
  FROM radiology_hcpcs
  GROUP BY hadm_id
),
admissions_with_los AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) <= 4 
      THEN '1-4 days' 
      ELSE '5-8 days' 
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.hadm_id IN (SELECT hadm_id FROM acs_hadms)
    AND DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) BETWEEN 1 AND 8
)
SELECT 
  awl.los_group,
  CASE 
    WHEN pa.hadm_id IS NOT NULL THEN 'Primary' 
    ELSE 'Secondary' 
  END AS dx_type,
  AVG(COALESCE(ic.img_count, 0)) AS mean_count,
  MIN(COALESCE(ic.img_count, 0)) AS min_count,
  MAX(COALESCE(ic.img_count, 0)) AS max_count
FROM admissions_with_los awl
JOIN acs_hadms ah ON awl.hadm_id = ah.hadm_id
LEFT JOIN principal_acs pa ON awl.hadm_id = pa.hadm_id
LEFT JOIN imaging_counts ic ON awl.hadm_id = ic.hadm_id
GROUP BY awl.los_group, dx_type
ORDER BY awl.los_group, dx_type;