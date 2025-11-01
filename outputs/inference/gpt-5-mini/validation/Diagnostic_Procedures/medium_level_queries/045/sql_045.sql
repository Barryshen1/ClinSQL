WITH dvt_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
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
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    -- admission has at least one DVT diagnosis (text search on diagnosis description)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%deep vein%'
          OR LOWER(dd.long_title) LIKE '%venous thrombosis%'
          OR LOWER(dd.long_title) LIKE '%dvt%'
        )
    )
),

-- Aggregate HCPCS imaging/diagnostic events per admission (operational definition using keywords)
hcpcs_imaging_counts AS (
  SELECT
    he.hadm_id,
    COUNT(1) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON he.hcpcs_cd = dh.code
  WHERE (
    LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%ultrasound%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%doppler%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%duplex%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%venous%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%ct%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%computed tomography%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%x-ray%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%radiograph%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%mri%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%magnetic resonance%'
    OR LOWER(COALESCE(dh.short_description, he.short_description, '')) LIKE '%vascular%'
  )
  GROUP BY he.hadm_id
)

-- Combine and compute final summaries
SELECT
  ca.icu_flag,
  ca.los_bucket,
  COUNT(1) AS admissions_count,
  ROUND(AVG(ca.imaging_count), 2) AS mean_noninvasive_diagnostics_per_admission
FROM (
  SELECT
    da.subject_id,
    da.hadm_id,
    da.anchor_age,
    da.gender,
    da.admittime,
    da.dischtime,
    da.los_days,
    da.icu_flag,
    -- LOS bucket: only keep 1-4 and 5-8
    CASE
      WHEN da.los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN da.los_days BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_bucket,
    COALESCE(hic.imaging_count, 0) AS imaging_count
  FROM dvt_admissions da
  LEFT JOIN hcpcs_imaging_counts hic
    ON da.hadm_id = hic.hadm_id
) ca
WHERE ca.los_bucket IS NOT NULL
GROUP BY ca.icu_flag, ca.los_bucket
ORDER BY ca.icu_flag, ca.los_bucket;