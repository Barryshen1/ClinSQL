WITH tia_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND (
      LOWER(d_icd.long_title) LIKE '%tia%'
      OR LOWER(d_icd.long_title) LIKE '%transient ischemic attack%'
      OR d_icd.icd_code IN ('435.9', 'G45.9')
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND EXTRACT(DAY FROM (a.dischtime - a.admittime)) BETWEEN 1 AND 7
),
icu_flag AS (
  SELECT
    t.hadm_id,
    t.los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS used_icu
  FROM tia_patients t
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON t.hadm_id = i.hadm_id
),
ct_mri_counts AS (
  -- CT/MRI from ICU procedureevents
  SELECT
    a.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON a.hadm_id = pe.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%ct%' OR LOWER(di.label) LIKE '%mri%')
    AND di.linksto = 'procedureevents'
  GROUP BY a.hadm_id

  UNION ALL

  -- CT/MRI from HOSP hcpcsevents
  SELECT
    a.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON a.hadm_id = h.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%ct%'
     OR LOWER(dh.short_description) LIKE '%mri%'
  GROUP BY a.hadm_id
),
ct_mri_aggregated AS (
  SELECT
    hadm_id,
    SUM(ct_mri_count) AS ct_mri_count
  FROM ct_mri_counts
  GROUP BY hadm_id
),
final_data AS (
  SELECT
    i.los_days,
    i.used_icu,
    COALESCE(c.ct_mri_count, 0) AS ct_mri_count
  FROM icu_flag i
  LEFT JOIN ct_mri_aggregated c
    ON i.hadm_id = c.hadm_id
  WHERE i.los_days BETWEEN 1 AND 7
)
SELECT
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  used_icu,
  PERCENTILE_CONT(ct_mri_count, 0.5) AS median_ct_mri,
  PERCENTILE_CONT(ct_mri_count, 0.25) AS q1_ct_mri,
  PERCENTILE_CONT(ct_mri_count, 0.75) AS q3_ct_mri
FROM final_data
GROUP BY los_group, used_icu
ORDER BY los_group, used_icu;