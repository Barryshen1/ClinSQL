WITH hf_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    CASE
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
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
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND LOWER(dd.long_title) LIKE '%heart failure%'
),

ct_mri_procedures AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    REGEXP_CONTAINS(UPPER(dp.long_title), r'CT|MRI')
  GROUP BY
    p.hadm_id
)

SELECT
  h.diagnosis_type,
  h.los_group,
  AVG(COALESCE(c.ct_mri_count, 0)) AS mean_ct_mri_per_admission,
  MIN(COALESCE(c.ct_mri_count, 0)) AS min_ct_mri_per_admission,
  MAX(COALESCE(c.ct_mri_count, 0)) AS max_ct_mri_per_admission
FROM
  hf_admissions h
LEFT JOIN
  ct_mri_procedures c
  ON h.hadm_id = c.hadm_id
GROUP BY
  h.diagnosis_type,
  h.los_group
ORDER BY
  h.diagnosis_type,
  h.los_group;