WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
pancreatitis_admissions AS (
  SELECT
    af.hadm_id,
    af.los_days
  FROM
    admissions_filtered af
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    af.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code = '5770')
    OR (d.icd_version = 10 AND d.icd_code IN ('K8590', 'K8591', 'K8580', 'K8581', 'K8500', 'K8501', 'K8510', 'K8511', 'K8520', 'K8521', 'K8530', 'K8531'))
),
procedure_counts AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    COUNT(pr.hadm_id) AS ct_mri_count
  FROM
    pancreatitis_admissions pa
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON
    pa.hadm_id = pr.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  ON
    pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  WHERE
    UPPER(dp.long_title) LIKE '%CT%' AND UPPER(dp.long_title) LIKE '%ABDOMEN%'
    OR UPPER(dp.long_title) LIKE '%MRI%' AND UPPER(dp.long_title) LIKE '%ABDOMEN%'
  GROUP BY
    pa.hadm_id, pa.los_days
),
los_grouped AS (
  SELECT
    hadm_id,
    ct_mri_count,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM
    procedure_counts
)
SELECT
  los_group,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(ct_mri_count) AS mean_ct_mri_per_admission
FROM
  los_grouped
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group
ORDER BY
  los_group;