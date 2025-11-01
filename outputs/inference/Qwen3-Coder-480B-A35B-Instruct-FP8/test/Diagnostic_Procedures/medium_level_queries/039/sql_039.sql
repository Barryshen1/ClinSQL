WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN t.hadm_id IS NOT NULL THEN 'ICU'
      ELSE 'non-ICU'
    END AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` t
  ON
    a.hadm_id = t.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code
    AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND LOWER(d.long_title) LIKE '%asthma exacerbation%'
),
imaging_counts AS (
  SELECT
    c.hadm_id,
    c.icu_status,
    CASE
      WHEN c.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN c.los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    COUNT(o.result_name) AS ct_mri_count
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.omr` o
  ON
    c.subject_id = o.subject_id
    AND o.chartdate BETWEEN c.admittime AND c.dischtime
    AND (LOWER(o.result_name) LIKE '%ct%' OR LOWER(o.result_name) LIKE '%mri%')
  WHERE
    c.los_days BETWEEN 1 AND 8
  GROUP BY
    c.hadm_id, c.icu_status, los_group
)
SELECT
  icu_status,
  los_group,
  AVG(ct_mri_count) AS mean_ct_mri_per_admission,
  MIN(ct_mri_count) AS min_ct_mri_per_admission,
  MAX(ct_mri_count) AS max_ct_mri_per_admission
FROM
  imaging_counts
WHERE
  los_group IS NOT NULL
GROUP BY
  icu_status, los_group
ORDER BY
  icu_status, los_group;