WITH tia_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
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
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '435%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'G45%')
      OR
      LOWER(dd.long_title) LIKE '%transient ischemic attack%'
    )
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

procedure_counts AS (
  SELECT
    tp.hadm_id,
    tp.los_days,
    COUNT(pc.hadm_id) AS ct_mri_count
  FROM
    tia_patients tp
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pc
    ON tp.hadm_id = pc.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON pc.icd_code = dp.icd_code AND pc.icd_version = dp.icd_version
  WHERE
    REGEXP_CONTAINS(LOWER(dp.long_title), r'(ct|mri)')
  GROUP BY
    tp.hadm_id, tp.los_days
),

los_groups AS (
  SELECT
    hadm_id,
    ct_mri_count,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM
    procedure_counts
)

SELECT
  los_group,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(ct_mri_count) AS mean_ct_mri_per_admission
FROM
  los_groups
GROUP BY
  los_group
ORDER BY
  los_group;