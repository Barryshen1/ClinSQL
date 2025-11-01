WITH cohort AS (
  -- Select male patients aged 64–74 with TIA diagnosis and LOS 1–7 days
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND REGEXP_CONTAINS(LOWER(dd.long_title), r'(transient ischemic attack|tia)')
),
-- Ultrasound / echocardiography counts per admission
ultrasound_counts AS (
  SELECT
    c.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.charttime BETWEEN c.admittime AND c.dischtime
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE di.label IS NOT NULL
    AND (
         LOWER(di.label) LIKE '%ultrasound%'
      OR LOWER(di.label) LIKE '%echocardiography%'
      OR LOWER(di.label) LIKE '%echo%'
    )
  GROUP BY c.hadm_id
),
-- Helper: whether an admission has any ICU stay (presence of ICU)
icu_has_stay AS (
  SELECT hadm_id, 1 AS has_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
-- Combine and compute LOS groups (1-3 days, 4-7 days) and ICU stratification
final AS (
  SELECT
    CASE
      WHEN t.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN t.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group,
    CASE
      WHEN ic.has_icu = 1 THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_use,
    COALESCE(u.ultrasound_count, 0) AS ultrasound_count
  FROM cohort AS t
  LEFT JOIN ultrasound_counts AS u
    ON t.hadm_id = u.hadm_id
  LEFT JOIN icu_has_stay AS ic
    ON t.hadm_id = ic.hadm_id
  WHERE t.los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  icu_use,
  AVG(ultrasound_count) AS mean_ultrasounds_per_admission
FROM final
WHERE los_group IS NOT NULL
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;