WITH hf_diag AS (
  -- Identify which admissions have heart failure diagnostics, and whether HF is primary (seq_num=1) or only secondary
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) AS hf_primary_exists,
    MAX(CASE WHEN d.seq_num > 1 THEN 1 ELSE 0 END) AS hf_secondary_exists
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
  ON
    d.icd_code = ddi.icd_code
    AND COALESCE(CAST(d.icd_version AS STRING), '') = COALESCE(CAST(ddi.icd_version AS STRING), '')
  WHERE
    -- look for heart failure in the long title (case-insensitive)
    ddi.long_title IS NOT NULL
    AND LOWER(ddi.long_title) LIKE '%heart failure%'
  GROUP BY
    d.subject_id, d.hadm_id
),

ct_mri_hcpcs AS (
  -- Count CT/MRI HCPCS events per admission (hcpcsevents.chartdate is a DATE)
  SELECT
    h.hadm_id,
    COUNT(1) AS ct_mri_events
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON
    h.hcpcs_cd = d.code
  WHERE
    -- Only consider HCPCS with descriptions that likely indicate CT or MRI
    (REGEXP_CONTAINS(UPPER(CONCAT(COALESCE(d.short_description,''), ' ', COALESCE(d.long_description,''))),
                     r'\b(CT|CAT|COMPUTED TOMOGRAPHY|MRI|MAGNETIC RESONANCE)\b'))
  GROUP BY
    h.hadm_id
),

cohort AS (
  -- Admissions filtered by female, anchor_age 45-55, LOS 1-7 days, and HF primary/secondary classification
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    DATE(a.admittime) AS admit_date,
    DATE(a.dischtime) AS discharge_date,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE
      WHEN h.hf_primary_exists = 1 THEN 'primary'
      WHEN h.hf_primary_exists = 0 AND h.hf_secondary_exists = 1 THEN 'secondary'
      ELSE NULL
    END AS diagnosis_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  LEFT JOIN
    hf_diag h
  ON
    a.hadm_id = h.hadm_id
  WHERE
    a.hadm_id IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
    -- keep only admissions that have HF as primary or secondary
    AND (
      (h.hf_primary_exists = 1)
      OR (h.hf_primary_exists = 0 AND h.hf_secondary_exists = 1)
    )
)

SELECT
  c.diagnosis_type,
  CASE WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3' ELSE '4-7' END AS los_range,
  COUNT(1) AS admissions_n,
  ROUND(AVG(COALESCE(cm.ct_mri_events, 0)), 3) AS mean_ct_mri_per_admission,
  MIN(COALESCE(cm.ct_mri_events, 0)) AS min_ct_mri_per_admission,
  MAX(COALESCE(cm.ct_mri_events, 0)) AS max_ct_mri_per_admission
FROM
  cohort c
LEFT JOIN
  -- join CT/MRI counts only where hcpcs chartdate would fall inside admission; hcpcsevents has chartdate only,
  -- so we already aggregated by hadm_id in ct_mri_hcpcs (assumes events were billed to that hadm_id).
  ct_mri_hcpcs cm
ON
  c.hadm_id = cm.hadm_id
GROUP BY
  c.diagnosis_type,
  los_range
ORDER BY
  c.diagnosis_type,
  los_range;