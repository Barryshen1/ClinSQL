WITH heart_failure_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      (d.icd_version = 9 AND d.icd_code = '428')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
admissions_with_los AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN heart_failure_patients hfp ON a.subject_id = hfp.subject_id
  WHERE a.admittime IS NOT NULL 
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
admissions_with_los_group AS (
  SELECT 
    hadm_id,
    subject_id,
    los_days,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL 
    END AS los_group
  FROM admissions_with_los
  WHERE los_days BETWEEN 1 AND 8
),
admissions_with_icu_use AS (
  SELECT 
    a.*,
    CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_use
  FROM admissions_with_los_group a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON a.hadm_id = i.hadm_id
),
radiology_codes AS (
  SELECT DISTINCT code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_hcpcs
  WHERE LOWER(short_description) LIKE '%ct%'
     OR LOWER(short_description) LIKE '%cat scan%'
     OR LOWER(short_description) LIKE '%x-ray%'
     OR LOWER(short_description) LIKE '%radiograph%'
),
radiology_events_per_admission AS (
  SELECT 
    h.hadm_id,
    h.los_group,
    h.icu_use,
    COUNT(r.hcpcs_cd) AS radiology_count
  FROM admissions_with_icu_use h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents r 
    ON h.hadm_id = r.hadm_id
  INNER JOIN radiology_codes rc
    ON r.hcpcs_cd = rc.code
  WHERE h.los_group IS NOT NULL
  GROUP BY h.hadm_id, h.los_group, h.icu_use
)
SELECT
  los_group,
  icu_use,
  APPROX_QUANTILES(radiology_count, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(radiology_count, 100)[OFFSET(50)] AS percentile_50,
  APPROX_QUANTILES(radiology_count, 100)[OFFSET(75)] AS percentile_75
FROM radiology_events_per_admission
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;