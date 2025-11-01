WITH base_pop AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    DATE_DIFF(CAST(adm.dischtime AS DATE), CAST(adm.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 77 AND 87
),
icu_flagged AS (
  SELECT
    bp.*,
    CASE WHEN COUNT(icu.stay_id) > 0 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM base_pop bp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON bp.subject_id = icu.subject_id
    AND bp.hadm_id = icu.hadm_id
  GROUP BY bp.subject_id, bp.hadm_id, bp.gender, bp.anchor_age, bp.admittime, bp.dischtime, bp.los_days
),
los_grouped AS (
  SELECT
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS los_group
  FROM icu_flagged
),
imaging_events AS (
  SELECT
    he.subject_id,
    he.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS he
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS dh
    ON he.hcpcs_cd = dh.code
  WHERE LOWER(dh.long_description) LIKE '%ct%'
     OR LOWER(dh.long_description) LIKE '%mri%'
     OR LOWER(dh.short_description) LIKE '%ct%'
     OR LOWER(dh.short_description) LIKE '%mri%'
  GROUP BY he.subject_id, he.hadm_id
),
adm_with_counts AS (
  SELECT
    lg.subject_id,
    lg.hadm_id,
    lg.icu_status,
    lg.los_group,
    COALESCE(ie.imaging_count, 0) AS imaging_count
  FROM los_grouped lg
  LEFT JOIN imaging_events ie
    ON lg.subject_id = ie.subject_id
    AND lg.hadm_id = ie.hadm_id
  WHERE los_group IS NOT NULL
)
SELECT
  los_group,
  icu_status,
  ROUND(AVG(imaging_count),2) AS mean_ct_mri_per_adm,
  MIN(imaging_count) AS min_ct_mri_per_adm,
  MAX(imaging_count) AS max_ct_mri_per_adm
FROM adm_with_counts
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;