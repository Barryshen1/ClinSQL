WITH eligible_admissions AS (
  -- admissions for male patients aged 81-91 (inclusive)
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.hadm_id IS NOT NULL
),

hcpcs_procs AS (
  -- HCPCS/CPT-like events with ECG/telemetry keywords in short_description
  SELECT
    he.hadm_id,
    COALESCE(he.hcpcs_cd, '') AS code,
    he.short_description AS descr
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS he
  WHERE
    he.hadm_id IN (SELECT hadm_id FROM eligible_admissions)
    AND (
      LOWER(COALESCE(he.short_description, '')) LIKE '%ecg%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%ekg%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%electrocardiogram%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%telemetry%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%cardiac monitor%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%cardiac monitoring%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%rhythm%'
    )
),

icd_procs AS (
  -- ICD procedures with ECG/telemetry keywords in the long title
  SELECT
    pi.hadm_id,
    pi.icd_code AS code,
    dip.long_title AS descr
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
      ON pi.icd_code = dip.icd_code
      AND pi.icd_version = dip.icd_version
  WHERE
    pi.hadm_id IN (SELECT hadm_id FROM eligible_admissions)
    AND (
      LOWER(COALESCE(dip.long_title, '')) LIKE '%ecg%'
      OR LOWER(COALESCE(dip.long_title, '')) LIKE '%ekg%'
      OR LOWER(COALESCE(dip.long_title, '')) LIKE '%electrocardiogram%'
      OR LOWER(COALESCE(dip.long_title, '')) LIKE '%telemetry%'
      OR LOWER(COALESCE(dip.long_title, '')) LIKE '%cardiac monitor%'
      OR LOWER(COALESCE(dip.long_title, '')) LIKE '%cardiac monitoring%'
      OR LOWER(COALESCE(dip.long_title, '')) LIKE '%rhythm%'
    )
),

icu_procs AS (
  -- ICU procedureevents where the event value or the d_items.label matches ECG/telemetry keywords
  SELECT
    pe.hadm_id,
    CONCAT('ICU_ITEM_', CAST(pe.itemid AS STRING)) AS code,
    COALESCE(CAST(pe.value AS STRING), di.label) AS descr
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON pe.itemid = di.itemid
  WHERE
    pe.hadm_id IN (SELECT hadm_id FROM eligible_admissions)
    AND (
      LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%ecg%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%ekg%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%electrocardiogram%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%telemetry%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%cardiac monitor%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%cardiac monitoring%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%rhythm%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%ecg%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%ekg%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%electrocardiogram%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%telemetry%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%cardiac monitor%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%cardiac monitoring%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%rhythm%'
    )
),

all_proc_codes AS (
  -- Union all found codes for eligible admissions; null/empty codes are excluded
  SELECT hadm_id, code FROM hcpcs_procs WHERE code IS NOT NULL AND TRIM(code) <> ''
  UNION DISTINCT
  SELECT hadm_id, code FROM icd_procs WHERE code IS NOT NULL AND TRIM(code) <> ''
  UNION DISTINCT
  SELECT hadm_id, code FROM icu_procs WHERE code IS NOT NULL AND TRIM(code) <> ''
),

per_admission_counts AS (
  -- Count distinct procedure codes per admission (hadm_id)
  SELECT
    ea.subject_id,
    a.hadm_id,
    COUNT(DISTINCT apc.code) AS distinct_ecg_telemetry_codes
  FROM
    eligible_admissions AS ea
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON ea.hadm_id = a.hadm_id
    LEFT JOIN all_proc_codes AS apc
      ON a.hadm_id = apc.hadm_id
  GROUP BY
    ea.subject_id,
    a.hadm_id
)

-- Final: sample standard deviation of the distinct-code counts across admissions
SELECT
  STDDEV_SAMP(distinct_ecg_telemetry_codes) AS sd_distinct_ecg_telemetry_codes_per_admission,
  COUNT(*) AS admissions_count,
  MIN(distinct_ecg_telemetry_codes) AS min_count,
  MAX(distinct_ecg_telemetry_codes) AS max_count,
  AVG(distinct_ecg_telemetry_codes) AS mean_count
FROM
  per_admission_counts;