WITH cohort AS (
  -- Admissions for female patients aged 62-72 with a diagnosis suggestive of lower GI bleed
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE(a.admittime) AS adm_date,
    DATE(a.dischtime) AS disch_date,
    (DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1) AS los_days,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON dx.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON dicd.icd_code = dx.icd_code AND dicd.icd_version = dx.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    -- keyword approach for lower GI bleed diagnoses: hemorrhage + colon/rect/rectum/gastrointestinal
    AND LOWER(dicd.long_title) LIKE '%hemorrhag%'
    AND (
      LOWER(dicd.long_title) LIKE '%colon%'
      OR LOWER(dicd.long_title) LIKE '%rect%'
      OR LOWER(dicd.long_title) LIKE '%rectum%'
      OR LOWER(dicd.long_title) LIKE '%gastrointestinal%'
    )
    -- limit to admissions with valid times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- consider only admissions with LOS up to 7 days (we only analyze 1-7 days)
    AND (DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1) BETWEEN 1 AND 7
),

hcpcs_diag_counts AS (
  -- Count HCPCS events suggestive of non-invasive diagnostics occurring during the admission
  SELECT
    c.hadm_id,
    COUNT(*) AS hcpcs_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON h.hadm_id = c.hadm_id
    -- use chartdate for hcpcs (date-level)
    AND DATE(h.chartdate) BETWEEN c.adm_date AND c.disch_date
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON dh.code = h.hcpcs_cd
  WHERE (
    -- search descriptive fields for imaging/ECG/EEG/PFT keywords
    UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%XRAY%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%X-RAY%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%CT%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%MRI%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%ULTRASOUND%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%RADIO%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%IMAGING%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%ECG%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%EKG%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%EEG%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%PFT%'
    OR UPPER(COALESCE(CAST(h.short_description AS STRING), '')) LIKE '%SPIRO%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%XRAY%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%CT%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%MRI%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%ULTRASOUND%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%RADIO%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%IMAGING%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%ECG%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%EKG%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%EEG%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%PFT%'
    OR UPPER(COALESCE(CAST(dh.long_description AS STRING), '')) LIKE '%SPIRO%'
  )
  GROUP BY c.hadm_id
),

proc_diag_counts AS (
  -- Count ICU procedureevents suggestive of non-invasive diagnostics occurring during the admission
  SELECT
    c.hadm_id,
    COUNT(*) AS proc_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.hadm_id = c.hadm_id
    AND pe.starttime BETWEEN c.admittime AND c.dischtime
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE (
    UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%XRAY%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%X-RAY%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%CT%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%MRI%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%ULTRASOUND%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%RADIO%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%IMAGING%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%ECG%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%EKG%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%EEG%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%PFT%'
    OR UPPER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%SPIRO%'
    OR UPPER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%ECG%'  -- sometimes description in value
    OR UPPER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%EKG%'
    OR UPPER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%EEG%'
  )
  GROUP BY c.hadm_id
),

icu_flag AS (
  -- mark whether admission had any ICU stay
  SELECT
    c.hadm_id,
    CASE WHEN COUNT(i.stay_id) > 0 THEN TRUE ELSE FALSE END AS icu_present
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
),

per_admission AS (
  -- combine counts and cohort-level info
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.los_days,
    IF(ich.icu_present, 'ICU', 'Non-ICU') AS icu_status,
    COALESCE(hc.hcpcs_count, 0) + COALESCE(pc.proc_count, 0) AS num_noninv_diag
  FROM cohort c
  LEFT JOIN hcpcs_diag_counts hc ON hc.hadm_id = c.hadm_id
  LEFT JOIN proc_diag_counts pc ON pc.hadm_id = c.hadm_id
  LEFT JOIN icu_flag ich ON ich.hadm_id = c.hadm_id
)

-- final aggregation: mean number of non-invasive diagnostics per admission by LOS group and ICU status
SELECT
  icu_status,
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    ELSE 'other'
  END AS los_group,
  COUNT(*) AS admissions,
  ROUND(AVG(num_noninv_diag), 3) AS mean_noninvasive_diagnostics_per_admission
FROM per_admission
WHERE los_days BETWEEN 1 AND 7
GROUP BY icu_status, los_group
ORDER BY icu_status, los_group;