WITH asthma_admissions AS (
  -- Find admissions for men age 77-87 with asthma diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND (
      -- ICD-10 asthma: J45.x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J45'))
      -- ICD-9 asthma: 493.xx
      OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^493'))
    )
),
admission_los AS (
  -- Calculate length of stay and group
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    anchor_age,
    gender,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_group
  FROM asthma_admissions
),
icu_status AS (
  -- Mark admissions as ICU or non-ICU
  SELECT
    al.subject_id,
    al.hadm_id,
    al.los_group,
    IF(ic.hadm_id IS NOT NULL, 'ICU', 'non-ICU') AS icu_flag
  FROM admission_los al
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON al.hadm_id = ic.hadm_id
  WHERE al.los_group IS NOT NULL
),
ct_mri_procs AS (
  -- Find CT/MRI procedures per admission
  SELECT
    pr.subject_id,
    pr.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    -- CT: ICD-9 87.xx, MRI: ICD-9 88.xx
    (
      (pr.icd_version = 9 AND (REGEXP_CONTAINS(pr.icd_code, r'^87') OR REGEXP_CONTAINS(pr.icd_code, r'^88')))
      -- For ICD-10, imaging codes are not in procedures_icd, so we focus on ICD-9
    )
  GROUP BY pr.subject_id, pr.hadm_id
)
SELECT
  icu.los_group,
  icu.icu_flag,
  COUNT(DISTINCT icu.hadm_id) AS admission_count,
  AVG(IFNULL(proc.ct_mri_count, 0)) AS mean_ct_mri,
  MIN(IFNULL(proc.ct_mri_count, 0)) AS min_ct_mri,
  MAX(IFNULL(proc.ct_mri_count, 0)) AS max_ct_mri
FROM icu_status icu
LEFT JOIN ct_mri_procs proc
  ON icu.subject_id = proc.subject_id AND icu.hadm_id = proc.hadm_id
GROUP BY icu.los_group, icu.icu_flag
ORDER BY icu.los_group, icu.icu_flag;