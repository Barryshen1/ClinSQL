WITH
-- Get male patients aged 49-59
male_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
),

-- Get admissions with primary heart failure diagnosis
heart_failure_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    ) THEN TRUE ELSE FALSE END AS had_icu_stay
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1
    AND (
      -- ICD-9 codes for heart failure
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR
      -- ICD-10 codes for heart failure
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
    AND a.subject_id IN (SELECT subject_id FROM male_patients)
),

-- Count CT/MRI procedures per admission
ct_mri_counts AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN (
          -- ICD-9 procedure codes for CT/MRI
          (p.icd_version = 9 AND p.icd_code IN ('87.03', '87.04', '88.91', '88.92', '87.01', '87.02', '87.07', '87.08', '87.41', '87.42', '87.43', '87.44', '87.45', '87.46', '87.47', '87.48', '87.49', '87.51', '87.52', '87.53', '87.54', '87.55', '87.56', '87.57', '87.58', '87.59', '87.61', '87.62', '87.63', '87.64', '87.65', '87.66', '87.67', '87.68', '87.69', '87.71', '87.72', '87.73', '87.74', '87.75', '87.76', '87.77', '87.78', '87.79', '87.81', '87.82', '87.83', '87.84', '87.85', '87.86', '87.87', '87.88', '87.89', '87.91', '87.92', '87.93', '87.94', '87.95', '87.96', '87.97', '87.98', '87.99', '88.91', '88.92', '88.93', '88.94', '88.95', '88.96', '88.97', '88.98', '88.99'))
          OR
          -- ICD-10 procedure codes for CT/MRI
          (p.icd_version = 10 AND p.icd_code IN ('B201', 'B202', 'B203', 'B204', 'B205', 'B206', 'B207', 'B208', 'B209', 'B210', 'B211', 'B212', 'B213', 'B214', 'B215', 'B216', 'B217', 'B218', 'B219', 'B220', 'B221', 'B222', 'B223', 'B224', 'B225', 'B226', 'B227', 'B228', 'B229', 'B230', 'B231', 'B232', 'B233', 'B234', 'B235', 'B236', 'B237', 'B238', 'B239', 'B240', 'B241', 'B242', 'B243', 'B244', 'B245', 'B246', 'B247', 'B248', 'B249', 'B250', 'B251', 'B252', 'B253', 'B254', 'B255', 'B256', 'B257', 'B258', 'B259', 'B260', 'B261', 'B262', 'B263', 'B264', 'B265', 'B266', 'B267', 'B268', 'B269', 'B270', 'B271', 'B272', 'B273', 'B274', 'B275', 'B276', 'B277', 'B278', 'B279', 'B280', 'B281', 'B282', 'B283', 'B284', 'B285', 'B286', 'B287', 'B288', 'B289', 'B290', 'B291', 'B292', 'B293', 'B294', 'B295', 'B296', 'B297', 'B298', 'B299'))
          OR
          -- HCPCS codes for CT/MRI
          h.hcpcs_cd IN ('70450', '70460', '70470', '70480', '70490', '70491', '70492', '70496', '70498', '70540', '70542', '70543', '70544', '70545', '70546', '70547', '70548', '70549', '70551', '70552', '70553', '70554', '70555', '70557', '70558', '70559', '71250', '71260', '71270', '71275', '71550', '71551', '71552', '71555', '72125', '72126', '72127', '72128', '72129', '72130', '72131', '72132', '72133', '72141', '72142', '72146', '72147', '72148', '72149', '72156', '72157', '72158', '72159', '72170', '72191', '72192', '72193', '72194', '72195', '72196', '72197', '72198', '72199', '73200', '73201', '73202', '73206', '73218', '73219', '73220', '73221', '73222', '73223', '73700', '73701', '73702', '73706', '73718', '73719', '73720', '73721', '73722', '73723')
        ) THEN
          CASE
            WHEN p.icd_code IS NOT NULL THEN p.icd_code
            WHEN h.hcpcs_cd IS NOT NULL THEN h.hcpcs_cd
          END
      END
    ) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON p.hadm_id = h.hadm_id
  WHERE
    p.hadm_id IN (SELECT hadm_id FROM heart_failure_admissions)
  GROUP BY
    p.hadm_id
)

-- Final aggregation
SELECT
  CASE WHEN h.had_icu_stay THEN 'With ICU' ELSE 'Without ICU' END AS icu_status,
  CASE
    WHEN h.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN h.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Other LOS'
  END AS los_category,
  COUNT(DISTINCT h.hadm_id) AS admission_count,
  AVG(COALESCE(c.ct_mri_count, 0)) AS avg_ct_mri_per_admission
FROM
  heart_failure_admissions h
LEFT JOIN
  ct_mri_counts c
  ON h.hadm_id = c.hadm_id
WHERE
  h.los_days BETWEEN 1 AND 7
GROUP BY
  icu_status,
  los_category
ORDER BY
  icu_status,
  los_category;