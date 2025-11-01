WITH aki_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE WHEN diag.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS aki_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code
   AND diag.icd_version = dd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
      OR (LOWER(dd.long_title) LIKE '%acute kidney%injury%')
    )
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
mri_ct_counts AS (
  SELECT
    proc.hadm_id,
    COUNT(*) AS mri_ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON proc.icd_code = dp.icd_code
   AND proc.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%mri%'
     OR LOWER(dp.long_title) LIKE '%ct%'
  GROUP BY proc.hadm_id
),
aki_with_imaging AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.gender,
    a.anchor_age,
    a.los_days,
    CASE 
      WHEN a.los_days BETWEEN 1 AND 4 THEN 'LOS_1_4'
      WHEN a.los_days BETWEEN 5 AND 7 THEN 'LOS_5_7'
    END AS los_group,
    a.aki_type,
    COALESCE(m.mri_ct_count, 0) AS mri_ct_count
  FROM aki_admissions a
  LEFT JOIN mri_ct_counts m
    ON a.hadm_id = m.hadm_id
)
SELECT
  los_group,
  aki_type,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(AVG(mri_ct_count), 2) AS mean_mri_cts_per_admission
FROM aki_with_imaging
GROUP BY los_group, aki_type
ORDER BY los_group, aki_type;