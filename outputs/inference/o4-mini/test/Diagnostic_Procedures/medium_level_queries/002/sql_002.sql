WITH base_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND (
      (d.icd_version = 9  AND d.icd_code LIKE '435%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'G45%')
    )
),

icu_flags AS (
  SELECT DISTINCT
    hadm_id,
    TRUE AS used_icu
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

us_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS us_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    LOWER(short_description) LIKE '%ultrasound%'
    OR LOWER(short_description) LIKE '%echocardiogram%'
  GROUP BY
    hadm_id
)

SELECT
  CASE
    WHEN b.los BETWEEN 1 AND 3 THEN '1-3'
    ELSE '4-7'
  END AS los_group,
  CASE
    WHEN i.used_icu IS TRUE THEN 'ICU'
    ELSE 'No ICU'
  END AS icu_use,
  AVG(COALESCE(u.us_count, 0)) AS mean_ultrasounds_per_admission
FROM
  base_admissions b
  LEFT JOIN us_counts u
    ON b.hadm_id = u.hadm_id
  LEFT JOIN icu_flags i
    ON b.hadm_id = i.hadm_id
GROUP BY
  los_group,
  icu_use
ORDER BY
  icu_use,
  los_group;