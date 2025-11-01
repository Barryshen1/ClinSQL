WITH admissions_with_diagnosis AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
        ON d_icd.icd_code = d_diag.icd_code
        AND d_icd.icd_version = d_diag.icd_version
      WHERE
        d_icd.hadm_id = a.hadm_id
        AND d_diag.long_title LIKE '%acute pancreatitis%'
    )
),
ct_mri_count AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE
    d.short_description LIKE '%CT%'
    OR d.short_description LIKE '%MRI%'
    OR d.long_description LIKE '%CT%'
    OR d.long_description LIKE '%MRI%'
  GROUP BY
    h.hadm_id
)
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_group,
  COUNT(*) AS patient_count,
  AVG(ct_mri_count) AS mean_procedures
FROM (
  SELECT
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COALESCE(c.ct_mri_count, 0) AS ct_mri_count
  FROM
    admissions_with_diagnosis a
  LEFT JOIN
    ct_mri_count c
    ON a.hadm_id = c.hadm_id
) sub
WHERE
  los_days BETWEEN 1 AND 8
GROUP BY
  los_group;