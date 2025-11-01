WITH tia_adms AS (
  -- Admissions for male patients age 90-100 with a TIA diagnosis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (
      LOWER(IFNULL(dd.long_title, '')) LIKE '%transient ischemic attack%'
      OR LOWER(IFNULL(dd.long_title, '')) LIKE '%transient cerebral ischemia%'
      OR LOWER(IFNULL(dd.long_title, '')) LIKE '%transient ischemia%'
    )
),

imaging_counts AS (
  -- Count distinct imaging procedure events (deduplicated by code + date) per admission,
  -- restricting events to occur during the admission
  SELECT
    e.hadm_id,
    COUNT(DISTINCT CONCAT(e.proc_code, CAST(e.proc_date AS STRING))) AS imaging_count
  FROM (
    -- HCPCS / CPT events
    SELECT
      h.hadm_id,
      h.chartdate AS proc_date,
      CONCAT('hcpcs_', h.hcpcs_cd) AS proc_code,
      LOWER(IFNULL(dh.long_description, '')) AS desc_text
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
      ON h.hcpcs_cd = dh.code

    UNION ALL

    -- ICD procedure events
    SELECT
      p.hadm_id,
      p.chartdate AS proc_date,
      CONCAT('icdproc_', p.icd_code) AS proc_code,
      LOWER(IFNULL(dp.long_title, '')) AS desc_text
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  ) e
  JOIN tia_adms ta
    ON e.hadm_id = ta.hadm_id
    AND CAST(e.proc_date AS DATE) BETWEEN CAST(ta.admittime AS DATE) AND CAST(ta.dischtime AS DATE)
  WHERE REGEXP_CONTAINS(
    IFNULL(e.desc_text, ''),
    r'\b(ct|mri|magnetic resonance|computed tomography|x-?ray|radiograph|ultrasound|sonography|angiograph|nuclear medicine|pet)\b'
  )
  GROUP BY e.hadm_id
)

SELECT
  CASE
    WHEN ta.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN ta.los_days BETWEEN 4 AND 7 THEN '4-7'
  END AS los_group,
  ROUND(AVG(COALESCE(ic.imaging_count, 0)), 2) AS mean_imaging_procs_per_admission,
  MIN(COALESCE(ic.imaging_count, 0)) AS min_imaging_procs_per_admission,
  MAX(COALESCE(ic.imaging_count, 0)) AS max_imaging_procs_per_admission,
  COUNT(*) AS admissions_in_group
FROM tia_adms ta
LEFT JOIN imaging_counts ic
  ON ta.hadm_id = ic.hadm_id
WHERE (ta.los_days BETWEEN 1 AND 3) OR (ta.los_days BETWEEN 4 AND 7)
GROUP BY los_group
ORDER BY los_group;