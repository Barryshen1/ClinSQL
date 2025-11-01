WITH heart_failure_primary AS (
  SELECT a.subject_id, a.hadm_id, p.gender, p.anchor_age,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND di.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),
los_stratified AS (
  SELECT subject_id, hadm_id,
         CASE
           WHEN los_days BETWEEN 1 AND 4 THEN 'LOS_1_4'
           WHEN los_days BETWEEN 5 AND 7 THEN 'LOS_5_7'
           ELSE NULL
         END AS los_group
  FROM heart_failure_primary
  WHERE los_days BETWEEN 1 AND 7
),
icu_flagged AS (
  SELECT ls.subject_id, ls.hadm_id, ls.los_group,
         CASE WHEN icu.subject_id IS NOT NULL THEN 'ICU_Y' ELSE 'ICU_N' END AS icu_use
  FROM los_stratified ls
  LEFT JOIN (
    SELECT DISTINCT hadm_id, subject_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON ls.hadm_id = icu.hadm_id
),
ct_mri_counts AS (
  SELECT hadm_id, COUNT(*) AS ctmri_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ct%' 
     OR LOWER(dp.long_title) LIKE '%mri%'
  GROUP BY hadm_id
),
final AS (
  SELECT icu_flagged.los_group,
         icu_flagged.icu_use,
         COUNT(DISTINCT icu_flagged.hadm_id) AS admission_count,
         AVG(IFNULL(ct_mri_counts.ctmri_count, 0)) AS mean_ctmri_per_admission
  FROM icu_flagged
  LEFT JOIN ct_mri_counts
    ON icu_flagged.hadm_id = ct_mri_counts.hadm_id
  WHERE icu_flagged.los_group IS NOT NULL
  GROUP BY icu_flagged.los_group, icu_flagged.icu_use
)
SELECT * FROM final
ORDER BY los_group, icu_use;