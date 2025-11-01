WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    ) THEN 1 ELSE 0 END AS icu_used
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%transient ischemic attack%'
          OR LOWER(dd.long_title) LIKE '%transient cerebral ischemia%'
          OR LOWER(dd.long_title) LIKE '%transient ischemic%'
          OR LOWER(dd.long_title) LIKE '%tia%'
        )
    )
),

-- HCPCS / CPT events that look like ultrasound/echocardiogram studies
hcpcs_events AS (
  SELECT
    h.hadm_id,
    h.chartdate AS evt_date,
    LOWER(IFNULL(h.short_description, '')) AS descr
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE (
    LOWER(IFNULL(h.short_description, '')) LIKE '%echocardi%'
    OR LOWER(IFNULL(h.short_description, '')) LIKE '%echo%'
    OR LOWER(IFNULL(h.short_description, '')) LIKE '%ultrasound%'
    OR LOWER(IFNULL(h.short_description, '')) LIKE '%ultrason%'
    OR LOWER(IFNULL(h.short_description, '')) LIKE '%doppler%'
    OR LOWER(IFNULL(h.short_description, '')) LIKE '%duplex%'
    OR LOWER(IFNULL(h.short_description, '')) LIKE '%carotid%'
    OR LOWER(IFNULL(d.long_description, '')) LIKE '%echocardi%'
    OR LOWER(IFNULL(d.long_description, '')) LIKE '%echo%'
    OR LOWER(IFNULL(d.long_description, '')) LIKE '%ultrasound%'
    OR LOWER(IFNULL(d.long_description, '')) LIKE '%ultrason%'
    OR LOWER(IFNULL(d.long_description, '')) LIKE '%doppler%'
    OR LOWER(IFNULL(d.long_description, '')) LIKE '%duplex%'
    OR LOWER(IFNULL(d.long_description, '')) LIKE '%carotid%'
  )
),

-- ICU procedureevents that look like ultrasound/echocardiogram studies
icu_proc_events AS (
  SELECT
    p.hadm_id,
    DATE(p.starttime) AS evt_date,
    LOWER(COALESCE(CAST(d.label AS STRING), CAST(p.value AS STRING))) AS descr
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON p.itemid = d.itemid
  WHERE (
    LOWER(COALESCE(CAST(d.label AS STRING), '')) LIKE '%echocardi%'
    OR LOWER(COALESCE(CAST(d.label AS STRING), '')) LIKE '%echo%'
    OR LOWER(COALESCE(CAST(d.label AS STRING), '')) LIKE '%ultrasound%'
    OR LOWER(COALESCE(CAST(d.label AS STRING), '')) LIKE '%ultrason%'
    OR LOWER(COALESCE(CAST(d.label AS STRING), '')) LIKE '%doppler%'
    OR LOWER(COALESCE(CAST(d.label AS STRING), '')) LIKE '%duplex%'
    OR LOWER(COALESCE(CAST(d.label AS STRING), '')) LIKE '%carotid%'
    OR LOWER(COALESCE(CAST(p.value AS STRING), '')) LIKE '%echocardi%'
    OR LOWER(COALESCE(CAST(p.value AS STRING), '')) LIKE '%echo%'
    OR LOWER(COALESCE(CAST(p.value AS STRING), '')) LIKE '%ultrasound%'
    OR LOWER(COALESCE(CAST(p.value AS STRING), '')) LIKE '%ultrason%'
    OR LOWER(COALESCE(CAST(p.value AS STRING), '')) LIKE '%doppler%'
    OR LOWER(COALESCE(CAST(p.value AS STRING), '')) LIKE '%duplex%'
    OR LOWER(COALESCE(CAST(p.value AS STRING), '')) LIKE '%carotid%'
  )
),

-- Union all detected events (count every matching row as one event)
union_events AS (
  SELECT hadm_id FROM hcpcs_events
  UNION ALL
  SELECT hadm_id FROM icu_proc_events
),

-- Count ultrasounds/echocardiograms per admission
per_admission_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS n_ultrasound
  FROM union_events
  GROUP BY hadm_id
),

-- Attach counts to cohort, set zero where none found, and derive LOS group
final_prep AS (
  SELECT
    c.*,
    COALESCE(pc.n_ultrasound, 0) AS n_ultrasound,
    CASE
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE 'other'
    END AS los_group
  FROM cohort c
  LEFT JOIN per_admission_counts pc
    ON c.hadm_id = pc.hadm_id
  WHERE c.los_days BETWEEN 1 AND 7
)

-- Aggregate: mean ultrasounds per admission by ICU use and LOS group
SELECT
  CASE WHEN icu_used = 1 THEN 'ICU used' ELSE 'No ICU' END AS icu_use,
  los_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(n_ultrasound), 3) AS mean_ultrasounds_per_admission,
  SUM(n_ultrasound) AS total_ultrasounds
FROM final_prep
WHERE los_group IN ('1-3', '4-7')
GROUP BY icu_used, los_group
ORDER BY icu_used DESC, los_group;