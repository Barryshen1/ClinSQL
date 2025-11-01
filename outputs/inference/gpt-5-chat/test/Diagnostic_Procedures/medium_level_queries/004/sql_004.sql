WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN SUM(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) > 0 THEN 'Primary'
      ELSE 'Secondary'
    END AS dx_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '428%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
  GROUP BY a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime
),
imaging_counts AS (
  SELECT
    pr.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE LOWER(dpr.long_title) LIKE '%computed tomography%'
     OR LOWER(dpr.long_title) LIKE '%ct %'
     OR LOWER(dpr.long_title) LIKE 'ct%'
     OR LOWER(dpr.long_title) LIKE '%magnetic resonance%'
     OR LOWER(dpr.long_title) LIKE '%mri%'
  GROUP BY pr.hadm_id
),
joined AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.dx_type,
    h.los,
    CASE
      WHEN h.los BETWEEN 1 AND 3 THEN '1-3 days'
      ELSE '4-7 days'
    END AS los_group,
    IFNULL(ic.imaging_count, 0) AS imaging_count
  FROM hf_admissions h
  LEFT JOIN imaging_counts ic
    ON h.hadm_id = ic.hadm_id
)
SELECT
  dx_type,
  los_group,
  ROUND(AVG(imaging_count),2) AS mean_ct_mri_per_adm,
  MIN(imaging_count) AS min_ct_mri_per_adm,
  MAX(imaging_count) AS max_ct_mri_per_adm
FROM joined
GROUP BY dx_type, los_group
ORDER BY dx_type, los_group;