WITH tia_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group,
    CASE 
      WHEN i.stay_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS icu_used
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (LOWER(dicd.long_title) LIKE '%tia%'
         OR LOWER(dicd.long_title) LIKE '%transient ischemic attack%')
),

imaging_counts AS (
  SELECT
    tp.hadm_id,
    tp.los_group,
    tp.icu_used,
    COUNT(h.hcpcs_cd) AS imaging_count
  FROM tia_patients tp
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.hcpcsevents h
    ON tp.hadm_id = h.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_hcpcs dh
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%ct%'
     OR LOWER(dh.short_description) LIKE '%mri%'
     OR LOWER(dh.short_description) LIKE '%ultrasound%'
     OR LOWER(dh.short_description) LIKE '%angiography%'
     OR LOWER(dh.short_description) LIKE '%x-ray%'
     OR LOWER(dh.short_description) LIKE '%radiograph%'
     OR LOWER(dh.short_description) LIKE '%nuclear medicine%'
     OR LOWER(dh.short_description) LIKE '%scan%'
     OR LOWER(dh.short_description) LIKE '%imaging%'
  GROUP BY tp.hadm_id, tp.los_group, tp.icu_used
)

SELECT
  los_group,
  icu_used,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(24)] AS p25,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(49)] AS p50,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(74)] AS p75
FROM imaging_counts
WHERE los_group IS NOT NULL
GROUP BY los_group, icu_used
ORDER BY los_group, icu_used;