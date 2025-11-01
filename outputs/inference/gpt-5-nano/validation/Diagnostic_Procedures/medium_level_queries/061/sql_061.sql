WITH
  -- Hadm_ids for eligible AKI admissions in the 64-74 female cohort
  female_aki_hadm AS (
    SELECT DISTINCT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON p.subject_id = d.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 64 AND 74
      AND d.icd_code LIKE 'N17%'
      AND d.icd_version = 10
  ),

  -- Primary vs secondary AKI per admission
  aki_diag_class AS (
    SELECT d.hadm_id,
           CASE
             WHEN MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
             ELSE 'secondary'
           END AS diag_group
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    WHERE d.hadm_id IN (SELECT hadm_id FROM female_aki_hadm)
      AND d.icd_code LIKE 'N17%'
      AND d.icd_version = 10
    GROUP BY d.hadm_id
  ),

  -- Admissions that are AKI-positive in the female 64-74 cohort with diagnosed AKI
  admissions_aki AS (
    SELECT a.hadm_id,
           a.admittime,
           a.dischtime,
           ac.diag_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN female_aki_hadm AS f ON f.hadm_id = a.hadm_id
    JOIN aki_diag_class AS ac ON ac.hadm_id = a.hadm_id
  ),

  -- Imaging events per admission bucketed by length-of-stay
  imaging_counts AS (
    SELECT ah.hadm_id,
           CASE
             WHEN TIMESTAMP_DIFF(ah.dischtime, ah.admittime, DAY) + 1 BETWEEN 1 AND 3 THEN '1-3'
             WHEN TIMESTAMP_DIFF(ah.dischtime, ah.admittime, DAY) + 1 BETWEEN 4 AND 7 THEN '4-7'
             ELSE NULL
           END AS day_bucket,
           ah.diag_group,
           COUNT(*) AS imaging_count
    FROM admissions_aki AS ah
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ce.hadm_id = ah.hadm_id
     AND ce.charttime >= ah.admittime
     AND ce.charttime <= ah.dischtime
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON di.itemid = ce.itemid
     AND (
          LOWER(di.label) LIKE '%x-ray%'
          OR LOWER(di.label) LIKE '%ct%'
          OR LOWER(di.label) LIKE '%mri%'
          OR LOWER(di.label) LIKE '%ultrasound%'
          OR LOWER(di.label) LIKE '%radiograph%'
          OR LOWER(di.label) LIKE '%imaging%'
          OR LOWER(di.category) IN ('Imaging','Imaging studies','Radiology','DIAGNOSTIC IMAGING')
        )
    GROUP BY ah.hadm_id, day_bucket, ah.diag_group
  )

-- Final: approximate median (and Q1, Q3) imaging_count by (day_bucket, diag_group)
, summary AS (
  SELECT day_bucket,
         diag_group,
         APPROX_QUANTILES(imaging_count, 100) AS quantiles
  FROM imaging_counts
  WHERE day_bucket IS NOT NULL
  GROUP BY day_bucket, diag_group
)

SELECT day_bucket,
       diag_group,
       quantiles[OFFSET(50)] AS median_imaging,   -- approximate median
       quantiles[OFFSET(25)] AS q1_imaging,        -- approximate 25th percentile
       quantiles[OFFSET(75)] AS q3_imaging         -- approximate 75th percentile
FROM summary
ORDER BY day_bucket, diag_group;