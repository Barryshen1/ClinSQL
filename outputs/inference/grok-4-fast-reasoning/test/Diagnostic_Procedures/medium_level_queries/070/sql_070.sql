WITH cohort_hadm AS (
  SELECT 
    a.hadm_id,
    CASE 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) <= 4 THEN '1-4' 
      ELSE '5-8' 
    END AS los_group,
    CASE 
      WHEN EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) 
      THEN 1 ELSE 0 
    END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 8
),
hf_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE '428%' OR icd_code LIKE 'I50%'
),
imaging_counts AS (
  SELECT 
    c.hadm_id,
    c.los_group,
    c.icu_flag,
    COUNT(CASE 
      WHEN LOWER(COALESCE(d.short_description, '')) LIKE '%x-ray%' 
        OR LOWER(COALESCE(d.short_description, '')) LIKE '%ct%' 
        OR LOWER(COALESCE(d.short_description, '')) LIKE '%radiograph%'
      THEN 1 
    END) AS imaging_count
  FROM cohort_hadm c
  JOIN hf_adm h ON h.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` n 
    ON n.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON d.code = n.hcpcs_cd
  GROUP BY c.hadm_id, c.los_group, c.icu_flag
)
SELECT 
  los_group,
  CASE WHEN icu_flag = 1 THEN 'Yes' ELSE 'No' END AS icu_use,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] AS p75
FROM imaging_counts
GROUP BY los_group, icu_flag
ORDER BY los_group, icu_use;