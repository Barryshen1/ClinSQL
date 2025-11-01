WITH hf_diagnoses AS (
  -- flag heart-failure diagnoses by admission and seq_num
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_code,
    dd.long_title,
    LOWER(dd.long_title) AS long_title_lc,
    CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END AS is_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  USING (icd_code, icd_version)
),
hf_admissions AS (
  -- admissions for male patients age 67-77 that have any HF diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    -- determine whether HF is primary (seq_num = 1) or secondary (seq_num > 1)
    MAX(CASE WHEN hd.is_hf = 1 AND hd.seq_num = 1 THEN 1 ELSE 0 END) AS has_hf_primary,
    MAX(CASE WHEN hd.is_hf = 1 THEN 1 ELSE 0 END) AS has_hf_any
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  LEFT JOIN
    hf_diagnoses hd
  USING (subject_id, hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age, p.gender
  HAVING
    has_hf_any = 1
),
imaging_hcpcs AS (
  -- imaging events from hcpcsevents (hospital module)
  SELECT
    he.hadm_id,
    he.subject_id,
    he.chartdate,
    he.short_description,
    LOWER(COALESCE(he.short_description, '')) AS desc_lc,
    CAST(dh.category AS STRING) AS hcpcs_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
  ON he.hcpcs_cd = dh.code
  WHERE
    he.hadm_id IS NOT NULL
    AND (
      -- category indicates radiology/imaging
      (dh.category IS NOT NULL AND LOWER(CAST(dh.category AS STRING)) LIKE '%radiol%')
      OR (LOWER(he.short_description) LIKE '%ct %' OR LOWER(he.short_description) LIKE '% ct%' OR LOWER(he.short_description) LIKE '%computed tomography%')
      OR LOWER(he.short_description) LIKE '%mri%'
      OR LOWER(he.short_description) LIKE '%magnetic resonance%'
      OR LOWER(he.short_description) LIKE '%x-ray%' OR LOWER(he.short_description) LIKE '%xray%' OR LOWER(he.short_description) LIKE '%radiograph%'
      OR LOWER(he.short_description) LIKE '%ultrasound%' OR LOWER(he.short_description) LIKE '%echo%' OR LOWER(he.short_description) LIKE '%echocardiogram%'
      OR LOWER(he.short_description) LIKE '%angiograph%' OR LOWER(he.short_description) LIKE '%pet%' OR LOWER(he.short_description) LIKE '%spect%'
      OR LOWER(he.short_description) LIKE '%fluoroscop%'
      OR LOWER(he.short_description) LIKE '%nuclear%'
    )
),
imaging_procedureevents AS (
  -- imaging events from ICU procedureevents joined with d_items
  SELECT
    pe.hadm_id,
    pe.subject_id,
    pe.starttime AS charttime,
    di.label AS item_label,
    CAST(di.category AS STRING) AS item_category,
    LOWER(COALESCE(di.label, '')) AS label_lc,
    LOWER(COALESCE(CAST(di.category AS STRING), '')) AS category_lc
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON pe.itemid = di.itemid
  WHERE
    pe.hadm_id IS NOT NULL
    AND (
      (di.category IS NOT NULL AND LOWER(CAST(di.category AS STRING)) LIKE '%radiol%')
      OR LOWER(COALESCE(di.label, '')) LIKE '%ct %' OR LOWER(COALESCE(di.label, '')) LIKE '% ct%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%mri%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%magnetic resonance%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%x-ray%' OR LOWER(COALESCE(di.label, '')) LIKE '%xray%' OR LOWER(COALESCE(di.label, '')) LIKE '%radiograph%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%ultrasound%' OR LOWER(COALESCE(di.label, '')) LIKE '%echo%' OR LOWER(COALESCE(di.label, '')) LIKE '%echocardiogram%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%angiograph%' OR LOWER(COALESCE(di.label, '')) LIKE '%pet%' OR LOWER(COALESCE(di.label, '')) LIKE '%spect%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%fluoroscop%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%nuclear%'
    )
),
imaging_events_union AS (
  -- unify imaging events from both sources; each row is treated as one imaging study event
  SELECT hadm_id, subject_id, chartdate, short_description AS description
  FROM imaging_hcpcs
  UNION ALL
  SELECT hadm_id, subject_id, CAST(charttime AS DATE) AS chartdate, item_label AS description
  FROM imaging_procedureevents
),
imaging_counts AS (
  -- count imaging events per admission
  SELECT
    hadm_id,
    COUNT(1) AS imaging_count
  FROM
    imaging_events_union
  GROUP BY
    hadm_id
),
admissions_with_counts AS (
  -- join HF admissions with imaging counts and compute LOS bin
  SELECT
    ha.subject_id,
    ha.hadm_id,
    ha.admittime,
    ha.dischtime,
    -- LOS in days counting calendar days (same-day -> 1)
    TIMESTAMP_DIFF(ha.dischtime, ha.admittime, DAY) + 1 AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(ha.dischtime, ha.admittime, DAY) + 1 BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(ha.dischtime, ha.admittime, DAY) + 1 BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_bin,
    CASE
      WHEN ha.has_hf_primary = 1 THEN 'primary'
      ELSE 'secondary'
    END AS hf_position,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM
    hf_admissions ha
  LEFT JOIN
    imaging_counts ic
  USING (hadm_id)
  WHERE
    -- restrict to LOS 1-7 days inclusive for the two bins of interest
    TIMESTAMP_DIFF(ha.dischtime, ha.admittime, DAY) + 1 BETWEEN 1 AND 7
)
SELECT
  los_bin,
  hf_position,
  -- extract approximate percentiles (25th, 50th, 75th) from APPROX_QUANTILES(..., 100)
  quants[OFFSET(25)] AS p25_imaging_per_admission,
  quants[OFFSET(50)] AS p50_imaging_per_admission,
  quants[OFFSET(75)] AS p75_imaging_per_admission,
  COUNT(1) AS n_admissions
FROM (
  SELECT
    los_bin,
    hf_position,
    APPROX_QUANTILES(imaging_count, 100) AS quants
  FROM
    admissions_with_counts
  GROUP BY
    los_bin,
    hf_position
)
ORDER BY
  los_bin,
  hf_position;