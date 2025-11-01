WITH pop AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = a.hadm_id
      ) THEN 1 ELSE 0
    END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    -- TIA filter (ICD-9: 435.x, ICD-10: G45.x)
    AND REGEXP_CONTAINS(LOWER(dd.long_title), r'transient cerebral ischemic attack')
    AND a.dischtime IS NOT NULL
),
imaging_per_adm AS (
  SELECT
    p.hadm_id,
    p.icu_use,
    SUM(
      CASE
        WHEN pe.starttime BETWEEN p.admittime AND p.dischtime
             AND (
                   LOWER(di.category) LIKE '%imaging%'
                   OR LOWER(di.label) LIKE '%imaging%'
                   OR LOWER(di.label) LIKE '%radiology%'
                  )
        THEN 1
        ELSE 0
      END
    ) AS imaging_count
  FROM pop p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.hadm_id = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = pe.itemid
  GROUP BY p.hadm_id, p.icu_use
),
admissions_with_counts AS (
  SELECT
    p.hadm_id,
    p.icu_use,
    p.admittime,
    p.dischtime,
    TIMESTAMP_DIFF(p.dischtime, p.admittime, DAY) AS los_days,
    COALESCE(ip.imaging_count, 0) AS imaging_count
  FROM pop p
  LEFT JOIN imaging_per_adm ip
    ON ip.hadm_id = p.hadm_id
),
grouped AS (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group,
    icu_use,
    imaging_count
  FROM admissions_with_counts
  WHERE los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  icu_use,
  quantiles[OFFSET(1)] AS p25,
  quantiles[OFFSET(2)] AS p50,
  quantiles[OFFSET(3)] AS p75
FROM (
  SELECT
    los_group,
    icu_use,
    APPROX_QUANTILES(imaging_count, 4) AS quantiles
  FROM grouped
  GROUP BY los_group, icu_use
) AS q
ORDER BY los_group, icu_use;