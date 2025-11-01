WITH target_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 'ICU_Yes'
      ELSE 'ICU_No'
    END AS icu_use
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

ct_mri_counts AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    UPPER(dp.long_title) LIKE '%CT%' OR UPPER(dp.long_title) LIKE '%MRI%'
  GROUP BY
    p.hadm_id
)

SELECT
  t.los_group,
  t.icu_use,
  COUNT(t.hadm_id) AS admission_count,
  AVG(COALESCE(c.ct_mri_count, 0)) AS mean_ct_mri_per_admission
FROM
  target_admissions t
LEFT JOIN
  ct_mri_counts c
  ON t.hadm_id = c.hadm_id
GROUP BY
  t.los_group,
  t.icu_use
ORDER BY
  t.los_group,
  t.icu_use;