WITH
-- Get female patients aged 50-60
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 50 AND 60
),

-- Get admissions with TIA diagnosis
tia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      -- ICD-9 codes for TIA
      (d.icd_version = 9 AND d.icd_code LIKE '435.%')
      OR
      -- ICD-10 codes for TIA
      (d.icd_version = 10 AND d.icd_code LIKE 'G45.%')
    )
),

-- Get CT/MRI procedures per admission
ct_mri_procedures AS (
  SELECT
    ta.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN
          -- ICD-9 procedure codes for CT/MRI
          (p.icd_version = 9 AND p.icd_code IN ('87.03', '88.91'))
          OR
          -- ICD-10 procedure codes for CT/MRI
          (p.icd_version = 10 AND p.icd_code IN ('B300ZZZ', 'B310ZZZ'))
        THEN p.icd_code
      END
    ) +
    COUNT(DISTINCT
      CASE
        WHEN
          -- HCPCS codes for CT/MRI
          h.hcpcs_cd IN (
            '70450', '70451', '70452', '70453', '70454', '70455', '70456', '70457', '70458', '70459',
            '70460', '70461', '70462', '70463', '70464', '70465', '70466', '70467', '70468', '70469',
            '70470', '70471', '70472', '70473', '70474', '70475', '70476', '70477', '70478', '70479',
            '70480', '70481', '70482', '70483', '70484', '70485', '70486', '70487', '70488', '70489',
            '70490', '70491', '70492', '70493', '70494', '70495', '70496', '70497', '70498',
            '70551', '70552', '70553'
          )
        THEN h.hcpcs_cd
      END
    ) AS ct_mri_count
  FROM
    tia_admissions ta
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON ta.hadm_id = p.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h ON ta.hadm_id = h.hadm_id
  GROUP BY
    ta.hadm_id
),

-- Combine all data
final_data AS (
  SELECT
    CASE
      WHEN ta.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN ta.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group,
    COUNT(DISTINCT ta.hadm_id) AS patient_count,
    AVG(COALESCE(c.ct_mri_count, 0)) AS avg_ct_mri_per_admission
  FROM
    tia_admissions ta
  LEFT JOIN
    ct_mri_procedures c ON ta.hadm_id = c.hadm_id
  WHERE
    ta.los_days BETWEEN 1 AND 7
  GROUP BY
    los_group
)

-- Final aggregation
SELECT
  los_group,
  SUM(patient_count) AS total_patients,
  AVG(avg_ct_mri_per_admission) AS mean_ct_mri_per_admission
FROM
  final_data
GROUP BY
  los_group
ORDER BY
  los_group;