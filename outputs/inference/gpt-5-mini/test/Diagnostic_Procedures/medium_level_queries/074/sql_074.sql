WITH cohort AS (
  -- Admissions for female patients age 40-50 with ischemic-stroke diagnosis and LOS 1-7 days
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS hosp_los_days,
    p.anchor_age,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 7
    AND EXISTS (
      -- admission has an ischemic-stroke diagnosis (ICD-9 or ICD-10 description matching ischemic/infarct terms)
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
        ON dx.icd_code = ddi.icd_code
        AND dx.icd_version = ddi.icd_version
      WHERE dx.hadm_id = a.hadm_id
        AND (
          REGEXP_CONTAINS(LOWER(COALESCE(ddi.long_title, '')), r'(ischemi|infarct|cerebral infarction|cerebrovascular)')
        )
    )
),
imaging_events AS (
  -- procedures_icd entries that look like imaging
  SELECT
    p.hadm_id,
    'procedures_icd' AS src,
    p.seq_num,
    p.chartdate AS evt_date,
    ddi.long_title AS description
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` ddi
    ON p.icd_code = ddi.icd_code
    AND p.icd_version = ddi.icd_version
  WHERE ddi.long_title IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(ddi.long_title),
      r'(\bct\b|\bct scan\b|computed tomography|magnetic resonance|mri|x-?ray|radiograph|radiography|ultrasound|sonography|angiograph|angiogram|pet|nuclear medicine)'
    )

  UNION ALL

  -- hcpcsevents that look like imaging
  SELECT
    h.hadm_id,
    'hcpcsevents' AS src,
    h.seq_num,
    h.chartdate AS evt_date,
    h.short_description AS description
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE h.short_description IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(h.short_description),
      r'(ct scan|computed tomography|magnetic resonance|mri|x-?ray|radiograph|radiography|ultrasound|sonography|angiograph|angiogram|pet|nuclear medicine)'
    )

  UNION ALL

  -- ICU procedureevents where the item label looks like imaging
  SELECT
    pe.hadm_id,
    'icu_procedureevents' AS src,
    NULL AS seq_num,
    DATE(pe.starttime) AS evt_date,
    di.label AS description
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE di.label IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(di.label),
      r'(ct scan|computed tomography|magnetic resonance|mri|x-?ray|radiograph|radiography|ultrasound|sonography|angiograph|angiogram|pet|nuclear medicine)'
    )
),

imaging_counts_per_adm AS (
  -- Count imaging events per hadm_id. Use simple count of rows from the union above.
  SELECT
    hadm_id,
    COUNT(*) AS imaging_event_count
  FROM imaging_events
  WHERE hadm_id IS NOT NULL
  GROUP BY hadm_id
)

SELECT
  c.icu_flag,
  CASE
    WHEN c.hosp_los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN c.hosp_los_days BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'other'
  END AS los_bucket,
  COUNT(*) AS admissions_n,
  ROUND(AVG(COALESCE(ic.imaging_event_count, 0)), 2) AS mean_imaging_per_admission,
  MIN(COALESCE(ic.imaging_event_count, 0)) AS min_imaging_per_admission,
  MAX(COALESCE(ic.imaging_event_count, 0)) AS max_imaging_per_admission
FROM cohort c
LEFT JOIN imaging_counts_per_adm ic
  ON c.hadm_id = ic.hadm_id
WHERE c.hosp_los_days BETWEEN 1 AND 7
  AND c.hosp_los_days BETWEEN 1 AND 7  -- explicit; cohort already filters but double-check
  AND (c.hosp_los_days BETWEEN 1 AND 4 OR c.hosp_los_days BETWEEN 5 AND 7)
GROUP BY
  c.icu_flag,
  los_bucket
ORDER BY
  c.icu_flag,
  los_bucket;