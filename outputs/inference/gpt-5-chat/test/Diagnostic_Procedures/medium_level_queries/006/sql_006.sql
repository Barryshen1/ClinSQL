WITH sepsis_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.gender, pat.anchor_age,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
    ON dx.icd_code = dxd.icd_code AND dx.icd_version = dxd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
    AND LOWER(dxd.long_title) LIKE '%sepsis%'
    AND LOWER(dxd.long_title) NOT LIKE '%shock%'
),
ultrasound_counts AS (
  SELECT p.hadm_id, COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY p.hadm_id
),
icu_flags AS (
  SELECT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
base AS (
  SELECT s.subject_id, s.hadm_id,
         CASE WHEN icu.icu_flag = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_group,
         CASE
           WHEN s.los_days BETWEEN 1 AND 4 THEN '1-4'
           WHEN s.los_days BETWEEN 5 AND 8 THEN '5-8'
         END AS los_group,
         COALESCE(u.ultrasound_count, 0) AS ultrasounds_per_adm
  FROM sepsis_admissions s
  LEFT JOIN ultrasound_counts u
    ON s.hadm_id = u.hadm_id
  LEFT JOIN icu_flags icu
    ON s.hadm_id = icu.hadm_id
  WHERE s.los_days BETWEEN 1 AND 8
)
SELECT icu_group, los_group,
       COUNT(DISTINCT subject_id) AS patient_count,
       ROUND(AVG(ultrasounds_per_adm), 2) AS mean_ultrasounds_per_admission
FROM base
GROUP BY icu_group, los_group
ORDER BY icu_group, los_group;