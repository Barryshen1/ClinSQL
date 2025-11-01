WITH aki_diag AS (
  -- diagnoses that explicitly indicate acute kidney injury
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute kidney injury%'
),
aki_by_admission AS (
  -- classify each admission that has AKI as primary or secondary
  SELECT
    hadm_id,
    subject_id,
    MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) AS has_primary_aki,
    MAX(CASE WHEN seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary_aki
  FROM aki_diag
  GROUP BY hadm_id, subject_id
),
aki_classified AS (
  SELECT
    hadm_id,
    subject_id,
    CASE
      WHEN has_primary_aki = 1 THEN 'primary'
      WHEN has_secondary_aki = 1 THEN 'secondary'
      ELSE 'unknown'
    END AS aki_type
  FROM aki_by_admission
),
admissions_with_aki AS (
  -- join with admissions and patients; compute LOS days and LOS groups
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- LOS in days: same-day = 1
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1) AS los_days,
    CASE
      WHEN (TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1) BETWEEN 1 AND 4 THEN '1-4'
      WHEN (TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group,
    ak.aki_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN aki_classified ak
      ON a.hadm_id = ak.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    -- limit to LOS 1-7 (we only need 1-4 and 5-7)
    AND (TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1) BETWEEN 1 AND 7
),
imaging_counts AS (
  -- count CT/MRI hcpcs events during the admission (chartdate between admittime and dischtime)
  SELECT
    a.hadm_id,
    COUNT(1) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
      ON h.hcpcs_cd = dh.code
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON h.hadm_id = a.hadm_id
      -- require the billed chartdate to fall within the admission
      AND h.chartdate BETWEEN DATE(a.admittime) AND DATE(a.dischtime)
  WHERE
    -- look for CT/MRI mentions in short or long description
    REGEXP_CONTAINS(
      LOWER(CONCAT(COALESCE(dh.short_description, ''), ' ', COALESCE(dh.long_description, ''))),
      r'(\bct\b|\bmri\b|computed tomography|magnetic resonance)'
    )
  GROUP BY
    a.hadm_id
)
SELECT
  aw.aki_type AS aki_classification,
  aw.los_group AS los_group,
  COUNT(DISTINCT aw.subject_id) AS patient_count,
  COUNT(DISTINCT aw.hadm_id) AS admission_count,
  ROUND(AVG(COALESCE(ic.imaging_count, 0)), 3) AS mean_mri_ct_per_admission
FROM
  admissions_with_aki aw
  LEFT JOIN imaging_counts ic
    ON aw.hadm_id = ic.hadm_id
GROUP BY
  aw.aki_type,
  aw.los_group
ORDER BY
  aw.aki_type,
  aw.los_group;