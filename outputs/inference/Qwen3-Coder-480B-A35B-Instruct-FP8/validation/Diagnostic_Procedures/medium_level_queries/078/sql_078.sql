WITH tia_admissions AS (
  -- Get admissions with TIA diagnosis for female patients aged 88–98
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_category,
    MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_icu
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays icu
    ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(dd.long_title) LIKE '%transient ischemic attack%'
  GROUP BY
    a.hadm_id, a.subject_id, a.admittime, a.dischtime
  HAVING
    los_category IS NOT NULL
),

imaging_counts AS (
  -- Count CT/MRI procedures per admission
  SELECT
    t.hadm_id,
    t.los_category,
    t.had_icu,
    COUNT(proc.hadm_id) AS ct_mri_count
  FROM
    tia_admissions t
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd proc
    ON t.hadm_id = proc.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ct%' AND (LOWER(dp.long_title) LIKE '%head%' OR LOWER(dp.long_title) LIKE '%brain%')
    OR LOWER(dp.long_title) LIKE '%mri%' AND (LOWER(dp.long_title) LIKE '%head%' OR LOWER(dp.long_title) LIKE '%brain%')
  GROUP BY
    t.hadm_id, t.los_category, t.had_icu
)

-- Final aggregation: median (IQR) CT/MRI per admission by stay length and ICU use
SELECT
  los_category,
  had_icu,
  APPROX_QUANTILES(ct_mri_count, 2)[OFFSET(1)] AS median_ct_mri,
  APPROX_QUANTILES(ct_mri_count, 4)[OFFSET(1)] AS q1_ct_mri,
  APPROX_QUANTILES(ct_mri_count, 4)[OFFSET(3)] AS q3_ct_mri
FROM
  imaging_counts
GROUP BY
  los_category,
  had_icu
ORDER BY
  los_category,
  had_icu;