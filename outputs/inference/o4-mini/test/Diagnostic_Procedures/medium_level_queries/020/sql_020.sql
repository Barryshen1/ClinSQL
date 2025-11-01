WITH tia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND LOWER(dd.long_title) LIKE '%transient ischemic attack%'
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
los_buckets AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group
  FROM
    tia_admissions
  WHERE
    los_days BETWEEN 1 AND 7
),
icu_flag AS (
  SELECT
    lb.subject_id,
    lb.hadm_id,
    lb.los_group,
    CASE
      WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_use
  FROM
    los_buckets lb
    LEFT JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) icu
      ON lb.hadm_id = icu.hadm_id
),
imaging_counts AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON p.icd_code = dp.icd_code
      AND p.icd_version = dp.icd_version
  WHERE
    (
      LOWER(dp.long_title) LIKE '%tomograph%'
      OR LOWER(dp.long_title) LIKE '%x-ray%'
      OR LOWER(dp.long_title) LIKE '%radiograph%'
      OR LOWER(dp.long_title) LIKE '%ultrasound%'
      OR LOWER(dp.long_title) LIKE '%magnetic resonance%'
    )
  GROUP BY
    p.hadm_id
)
SELECT
  icu.icu_use,
  icu.los_group,
  COUNT(DISTINCT icu.hadm_id) AS admission_count,
  ROUND(AVG(IFNULL(ic.imaging_count, 0)), 2) AS mean_imaging_per_admission
FROM
  icu_flag icu
  LEFT JOIN imaging_counts ic
    ON icu.hadm_id = ic.hadm_id
GROUP BY
  icu.icu_use,
  icu.los_group
ORDER BY
  icu.los_group,
  icu.icu_use;