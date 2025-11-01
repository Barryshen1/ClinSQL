WITH
-- Get female patients aged 47-57
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 47 AND 57
),

-- Get admissions with acute pancreatitis (ICD-10 K85.*)
pancreatitis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND di.icd_code LIKE 'K85.%'
    AND a.hospital_expire_flag = 0  -- Exclude patients who died in hospital
),

-- Get CT/MRI procedures from HCPCS events
ct_mri_procedures AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE
    (dh.short_description LIKE '%CT%' OR dh.short_description LIKE '%MRI%')
    AND h.hadm_id IN (SELECT hadm_id FROM pancreatitis_admissions)
  GROUP BY
    h.subject_id, h.hadm_id
),

-- Combine with ICU procedure events if needed (though most imaging is in HCPCS)
icu_ct_mri_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON p.itemid = di.itemid
  WHERE
    (di.label LIKE '%CT%' OR di.label LIKE '%MRI%')
    AND p.hadm_id IN (SELECT hadm_id FROM pancreatitis_admissions)
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Combine all procedures
all_procedures AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(procedure_count) AS total_procedures
  FROM (
    SELECT subject_id, hadm_id, procedure_count FROM ct_mri_procedures
    UNION ALL
    SELECT subject_id, hadm_id, procedure_count FROM icu_ct_mri_procedures
  )
  GROUP BY
    subject_id, hadm_id
),

-- Final dataset with LOS categories
final_dataset AS (
  SELECT
    pa.los_days,
    CASE
      WHEN pa.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN pa.los_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE 'Other'
    END AS los_category,
    COUNT(DISTINCT pa.subject_id) AS patient_count,
    AVG(COALESCE(ap.total_procedures, 0)) AS avg_procedures_per_admission
  FROM
    pancreatitis_admissions pa
  LEFT JOIN
    all_procedures ap
    ON pa.subject_id = ap.subject_id AND pa.hadm_id = ap.hadm_id
  WHERE
    pa.los_days BETWEEN 1 AND 8
  GROUP BY
    los_category, pa.los_days
)

-- Final result
SELECT
  los_category,
  SUM(patient_count) AS total_patients,
  AVG(avg_procedures_per_admission) AS mean_procedures_per_admission
FROM
  final_dataset
WHERE
  los_category IN ('1-4 days', '5-8 days')
GROUP BY
  los_category
ORDER BY
  los_category;