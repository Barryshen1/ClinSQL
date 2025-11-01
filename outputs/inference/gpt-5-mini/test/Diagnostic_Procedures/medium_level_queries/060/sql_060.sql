WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
         AND d.icd_version = dicd.icd_version
  WHERE
    d.seq_num = 1  -- primary diagnosis
    AND LOWER(dicd.long_title) LIKE '%heart failure%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    -- restrict to LOS 1-7 (we will bucket 1-4 and 5-7)
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),

-- Determine ICU use per admission
cohort_with_icu AS (
  SELECT
    c.*,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = c.hadm_id
    ) THEN 'ICU' ELSE 'No ICU' END AS icu_use,
    CASE
      WHEN DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_bucket
  FROM cohort_admissions c
),

-- Imaging events from hcpcsevents (hospital billing)
hcpcs_imaging AS (
  SELECT
    he.hadm_id,
    TIMESTAMP(he.chartdate) AS event_time,
    COALESCE(dh.long_description, he.short_description) AS description,
    -- classify as MRI if MRI keywords present, else CT if CT keywords present
    CASE
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(dh.long_description, he.short_description)), r'\bmri\b|magnetic resonance') THEN 'MRI'
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(dh.long_description, he.short_description)), r'\bct\b|computed tomography|cat scan') THEN 'CT'
      ELSE 'OTHER'
    END AS imaging_type
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON he.hcpcs_cd = dh.code
  WHERE
    -- match CT or MRI mentions in description
    REGEXP_CONTAINS(LOWER(COALESCE(dh.long_description, he.short_description)), r'\bmri\b|magnetic resonance|\bct\b|computed tomography|cat scan')
),

-- Imaging events from procedures_icd (hospital procedures)
proc_icd_imaging AS (
  SELECT
    p.hadm_id,
    TIMESTAMP(p.chartdate) AS event_time,
    dicp.long_title AS description,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(dicp.long_title), r'\bmri\b|magnetic resonance') THEN 'MRI'
      WHEN REGEXP_CONTAINS(LOWER(dicp.long_title), r'\bct\b|computed tomography|cat scan') THEN 'CT'
      ELSE 'OTHER'
    END AS imaging_type
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicp
    ON p.icd_code = dicp.icd_code
       AND p.icd_version = dicp.icd_version
  WHERE
    REGEXP_CONTAINS(LOWER(COALESCE(dicp.long_title, '')), r'\bmri\b|magnetic resonance|\bct\b|computed tomography|cat scan')
),

-- Imaging events from ICU procedureevents (charted procedures)
procedureevents_imaging AS (
  SELECT
    pe.hadm_id,
    SAFE_CAST(pe.starttime AS TIMESTAMP) AS event_time,
    di.label AS description,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(di.label), r'\bmri\b|magnetic resonance') THEN 'MRI'
      WHEN REGEXP_CONTAINS(LOWER(di.label), r'\bct\b|computed tomography|cat scan') THEN 'CT'
      ELSE 'OTHER'
    END AS imaging_type
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE
    REGEXP_CONTAINS(LOWER(COALESCE(di.label, '')), r'\bmri\b|magnetic resonance|\bct\b|computed tomography|cat scan')
),

-- Union all candidate imaging events and filter to CT or MRI only
all_imaging_events_raw AS (
  SELECT hadm_id, event_time, imaging_type FROM hcpcs_imaging
  UNION ALL
  SELECT hadm_id, event_time, imaging_type FROM proc_icd_imaging
  UNION ALL
  SELECT hadm_id, event_time, imaging_type FROM procedureevents_imaging
),

-- Normalize and deduplicate imaging events per admission by (hadm_id, event_date, imaging_type)
all_imaging_events AS (
  SELECT
    hadm_id,
    DATE(event_time) AS event_date,
    imaging_type
  FROM all_imaging_events_raw
  WHERE imaging_type IN ('CT', 'MRI')
  GROUP BY hadm_id, DATE(event_time), imaging_type
),

-- Count imaging events per admission
imaging_counts_per_adm AS (
  SELECT
    hadm_id,
    COUNT(1) AS imaging_count
  FROM all_imaging_events
  GROUP BY hadm_id
)

-- Final aggregation: admissions by LOS bucket x ICU use with admission counts and mean CT/MRI per admission
SELECT
  cw.los_bucket,
  cw.icu_use,
  COUNT(*) AS admission_count,
  ROUND(AVG(COALESCE(ic.imaging_count, 0)), 3) AS mean_ct_mri_per_admission
FROM cohort_with_icu cw
LEFT JOIN imaging_counts_per_adm ic
  ON cw.hadm_id = ic.hadm_id
WHERE cw.los_bucket IS NOT NULL
GROUP BY cw.los_bucket, cw.icu_use
ORDER BY cw.los_bucket, cw.icu_use;