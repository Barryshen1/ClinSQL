WITH heart_failure_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
filtered_admissions AS (
  SELECT 
    hadm_id,
    subject_id,
    los_days
  FROM heart_failure_admissions
  WHERE age_at_admission BETWEEN 59 AND 69
    AND los_days BETWEEN 1 AND 8
),
icu_use_flag AS (
  SELECT 
    f.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_use
  FROM filtered_admissions f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON f.hadm_id = i.hadm_id
),
radiology_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS radiology_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.long_description) LIKE '%radiograph%'
    OR LOWER(d.long_description) LIKE '%x-ray%'
    OR LOWER(d.long_description) LIKE '%ct%'
    OR LOWER(d.long_description) LIKE '%computed tomography%'
  GROUP BY h.hadm_id
),
admission_summary AS (
  SELECT 
    f.hadm_id,
    f.los_days,
    i.icu_use,
    COALESCE(r.radiology_count, 0) AS radiology_count
  FROM filtered_admissions f
  INNER JOIN icu_use_flag i
    ON f.hadm_id = i.hadm_id
  LEFT JOIN radiology_counts r
    ON f.hadm_id = r.hadm_id
)
SELECT 
  icu_use,
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
  END AS los_group,
  APPROX_QUANTILES(radiology_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(radiology_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(radiology_count, 100)[OFFSET(75)] AS p75
FROM admission_summary
GROUP BY icu_use, los_group
ORDER BY icu_use, los_group;