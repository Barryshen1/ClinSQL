WITH dvt_patients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND LOWER(ddx.long_title) LIKE '%deep vein thrombosis%'
),
los_classified AS (
  SELECT
    subject_id,
    hadm_id,
    anchor_age,
    gender,
    admittime,
    dischtime,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN 'LOS_1_4'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 8 THEN 'LOS_5_8'
      ELSE NULL
    END AS los_group
  FROM dvt_patients
),
icu_flag AS (
  SELECT DISTINCT hadm_id, 'ICU' AS icu_status
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
noninvasive_counts AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS noninvasive_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%noninvasive%'
  GROUP BY p.hadm_id
),
final AS (
  SELECT
    l.los_group,
    IF(i.hadm_id IS NOT NULL, 'ICU', 'no_ICU') AS icu_status,
    COUNT(DISTINCT l.hadm_id) AS admission_count,
    ROUND(AVG(IFNULL(n.noninvasive_count, 0)), 2) AS mean_noninvasive_per_adm
  FROM los_classified l
  LEFT JOIN icu_flag i
    ON l.hadm_id = i.hadm_id
  LEFT JOIN noninvasive_counts n
    ON l.hadm_id = n.hadm_id
  WHERE l.los_group IS NOT NULL
  GROUP BY l.los_group, icu_status
)
SELECT *
FROM final
ORDER BY los_group, icu_status;