WITH base_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_adm,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 78 AND 88
),
dvt_admissions AS (
  SELECT DISTINCT ba.*
  FROM base_admissions ba
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ba.subject_id = di.subject_id AND ba.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%deep vein%'
     OR LOWER(dd.long_title) LIKE '%dvt%'
     OR LOWER(dd.long_title) LIKE '%thrombophlebitis%'
),
admissions_with_icu AS (
  SELECT 
    da.*,
    CASE WHEN i.subject_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_stay
  FROM dvt_admissions da
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i
    ON da.subject_id = i.subject_id AND da.hadm_id = i.hadm_id
),
filtered_adm AS (
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM admissions_with_icu
  WHERE los_days BETWEEN 1 AND 8
),
dimer_counts AS (
  SELECT 
    l.hadm_id,
    COUNT(l.labevent_id) AS num_dimer
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  WHERE l.hadm_id IS NOT NULL
    AND LOWER(li.label) LIKE '%d-dimer%'
    AND l.valuenum IS NOT NULL
  GROUP BY l.hadm_id
),
us_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS num_us
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE h.hcpcs_cd IN ('93970', '93971')
  GROUP BY h.hadm_id
)
SELECT 
  f.los_group,
  f.icu_stay,
  COUNT(*) AS num_admissions,
  AVG(COALESCE(dc.num_dimer, 0) + COALESCE(uc.num_us, 0)) AS mean_noninvasive_diagnostics
FROM filtered_adm f
LEFT JOIN dimer_counts dc
  ON f.hadm_id = dc.hadm_id
LEFT JOIN us_counts uc
  ON f.hadm_id = uc.hadm_id
WHERE f.los_group IS NOT NULL
GROUP BY f.los_group, f.icu_stay
ORDER BY f.los_group, f.icu_stay;