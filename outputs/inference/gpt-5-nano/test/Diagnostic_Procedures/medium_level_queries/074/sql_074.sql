WITH cohort_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'Female'
    AND p.anchor_age BETWEEN 40 AND 50
    AND dd.long_title LIKE '%ischemic stroke%'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
-- Step 2: ICU flag per admission (1 if there is an ICU stay for this admission, else 0)
icu_flag AS (
  SELECT
    ca.hadm_id,
    ca.subject_id,
    ca.LOS,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        WHERE icu.hadm_id = ca.hadm_id
          AND icu.subject_id = ca.subject_id
      ) THEN 1
      ELSE 0
    END AS is_in_icu
  FROM cohort_admissions AS ca
),
-- Step 3: imaging counts per admission
imaging_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS he
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS dc
    ON he.hcpcs_cd = dc.code
  WHERE
    LOWER(dc.long_description) LIKE '%imaging%'
    OR LOWER(he.short_description) LIKE '%ct%'
    OR LOWER(he.short_description) LIKE '%mri%'
    OR LOWER(he.short_description) LIKE '%x-ray%'
    OR LOWER(he.short_description) LIKE '%xray%'
    OR LOWER(he.short_description) LIKE '%ultrasound%'
  GROUP BY hadm_id
)

-- Step 4: assemble and compute statistics by LOS group and ICU status
SELECT
  los_group AS los_group,
  is_in_icu AS is_in_icu,
  AVG(imaging_count) AS mean_imaging_per_admission,
  MIN(imaging_count) AS min_imaging_per_admission,
  MAX(imaging_count) AS max_imaging_per_admission
FROM (
  SELECT
    i.is_in_icu,
    CASE
      WHEN i.LOS BETWEEN 1 AND 4 THEN '1-4'
      WHEN i.LOS BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM icu_flag AS i
  LEFT JOIN imaging_counts ic
    ON i.hadm_id = ic.hadm_id
  WHERE i.LOS BETWEEN 1 AND 7
    AND (CASE
           WHEN i.LOS BETWEEN 1 AND 4 THEN '1-4'
           WHEN i.LOS BETWEEN 5 AND 7 THEN '5-7'
         END) IS NOT NULL
) t
GROUP BY los_group, is_in_icu
ORDER BY los_group, is_in_icu;