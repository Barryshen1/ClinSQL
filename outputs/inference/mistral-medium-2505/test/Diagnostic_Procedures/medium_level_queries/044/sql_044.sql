WITH
-- Get female patients aged 62-72
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 62 AND 72
),

-- Get admissions with LOS calculation
admissions_with_los AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_icu_stay
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients fp ON a.subject_id = fp.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    a.dischtime IS NOT NULL
),

-- Get non-invasive diagnostic procedures
non_invasive_diagnostics AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.hcpcs_cd,
    d.long_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE
    -- Filter for non-invasive diagnostic procedures using long_description
    (d.long_description LIKE '%radiology%'
     OR d.long_description LIKE '%imaging%'
     OR d.long_description LIKE '%x-ray%'
     OR d.long_description LIKE '%ct%'
     OR d.long_description LIKE '%mri%'
     OR d.long_description LIKE '%ultrasound%'
     OR d.long_description LIKE '%echocardiogram%'
     OR d.long_description LIKE '%ecg%'
     OR d.long_description LIKE '%ekg%'
     OR d.long_description LIKE '%eeg%'
     OR d.long_description LIKE '%pulmonary function%'
     OR d.long_description LIKE '%pft%')
    -- Also include specific HCPCS codes for common non-invasive diagnostics
    OR h.hcpcs_cd IN (
      '71010', '71020', '71030', '71034', '71035', '71040', '71045', '71046', '71047', '71048', -- Chest X-rays
      '78451', '78452', '78453', '78454', '78466', '78468', '78469', '78472', '78473', -- Cardiac imaging
      '93000', '93005', '93010', '93015', '93040', '93041', '93042', -- ECG/EKG
      '95812', '95813', '95816', '95819', '95822', '95827', '95829', -- EEG
      '94010', '94011', '94012', '94013', '94014', '94015', '94016', '94017', '94018', '94060' -- PFT
    )
),

-- Count diagnostics per admission
diagnostics_count AS (
  SELECT
    a.hadm_id,
    a.los_days,
    a.has_icu_stay,
    COUNT(DISTINCT n.hcpcs_cd) AS num_non_invasive_diagnostics
  FROM
    admissions_with_los a
  LEFT JOIN
    non_invasive_diagnostics n ON a.subject_id = n.subject_id AND a.hadm_id = n.hadm_id
  GROUP BY
    a.hadm_id, a.los_days, a.has_icu_stay
)

-- Final aggregation by LOS and ICU status
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other'
  END AS los_category,
  CASE
    WHEN has_icu_stay THEN 'ICU'
    ELSE 'Non-ICU'
  END AS icu_status,
  AVG(num_non_invasive_diagnostics) AS mean_non_invasive_diagnostics,
  COUNT(*) AS num_admissions
FROM
  diagnostics_count
WHERE
  los_days BETWEEN 1 AND 7
GROUP BY
  los_category, icu_status
ORDER BY
  los_category, icu_status;