WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN MIN(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS hf_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
  GROUP BY a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime
),
imaging_counts AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    COUNT(*) AS mri_ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ct%'
     OR LOWER(dp.long_title) LIKE '%mri%'
  GROUP BY pr.subject_id, pr.hadm_id
),
los_and_imaging AS (
  SELECT
    hfa.hadm_id,
    hfa.hf_type,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    IFNULL(ic.mri_ct_count, 0) AS mri_ct_count
  FROM (
    SELECT *,
           DATE_DIFF(dischtime, admittime, DAY) AS los_days
    FROM hf_admissions
  ) hfa
  LEFT JOIN imaging_counts ic
    ON hfa.subject_id = ic.subject_id AND hfa.hadm_id = ic.hadm_id
  WHERE los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  hf_type,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(mri_ct_count) AS mean_mri_ct_per_admission
FROM los_and_imaging
GROUP BY los_group, hf_type
ORDER BY los_group, hf_type;