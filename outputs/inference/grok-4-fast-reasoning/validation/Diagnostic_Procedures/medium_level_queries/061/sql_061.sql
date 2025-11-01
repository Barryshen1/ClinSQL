WITH eligible_adms AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    FLOOR(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - 2008) AS age_at_adm,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND FLOOR(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - 2008) BETWEEN 64 AND 74
    AND a.hadm_id IS NOT NULL
),
aki_adms AS (
  SELECT 
    ea.*,
    EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = ea.hadm_id 
        AND (di.icd_code LIKE '584%' OR di.icd_code LIKE 'N17%')
    ) AS has_aki,
    EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = ea.hadm_id 
        AND di.seq_num = 1 
        AND (di.icd_code LIKE '584%' OR di.icd_code LIKE 'N17%')
    ) AS is_primary_aki
  FROM eligible_adms ea
),
filtered_adms AS (
  SELECT * 
  FROM aki_adms 
  WHERE has_aki
),
with_los_bin AS (
  SELECT 
    *,
    CASE 
      WHEN los_days >= 1 AND los_days <= 3 THEN '1-3'
      WHEN los_days >= 4 AND los_days <= 7 THEN '4-7'
      ELSE 'other'
    END AS los_bin
  FROM filtered_adms
),
with_imaging AS (
  SELECT 
    wlb.*,
    (
      SELECT COUNT(*) 
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
        ON pi.icd_code = dip.icd_code 
        AND pi.icd_version = dip.icd_version
      WHERE pi.hadm_id = wlb.hadm_id
        AND (
          LOWER(dip.long_title) LIKE '%ct%' 
          OR LOWER(dip.long_title) LIKE '%computed tomography%'
          OR LOWER(dip.long_title) LIKE '%mri%' 
          OR LOWER(dip.long_title) LIKE '%magnetic resonance%'
          OR LOWER(dip.long_title) LIKE '%x-ray%' 
          OR LOWER(dip.long_title) LIKE '%radiograph%'
          OR LOWER(dip.long_title) LIKE '%ultrasound%' 
          OR LOWER(dip.long_title) LIKE '%sonography%'
          OR LOWER(dip.long_title) LIKE '%nuclear%'
        )
    ) AS num_imaging
  FROM with_los_bin wlb
),
adms_final AS (
  SELECT 
    los_bin,
    CASE WHEN is_primary_aki THEN 'primary' ELSE 'secondary' END AS aki_type,
    num_imaging
  FROM with_imaging
  WHERE los_bin != 'other'
)
SELECT 
  los_bin,
  aki_type,
  APPROX_QUANTILES(num_imaging, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(num_imaging, 4)[OFFSET(3)] - APPROX_QUANTILES(num_imaging, 4)[OFFSET(1)] AS iqr
FROM adms_final
GROUP BY los_bin, aki_type
ORDER BY los_bin, aki_type;