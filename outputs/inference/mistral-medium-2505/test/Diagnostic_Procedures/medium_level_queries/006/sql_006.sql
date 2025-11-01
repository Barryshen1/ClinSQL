WITH sepsis_patients AS (
  -- Identify male patients aged 48-58 with sepsis (no shock)
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      -- Sepsis ICD-9 codes (excluding septic shock)
      (d.icd_version = 9 AND d.icd_code IN ('995.91', '785.52') AND d.icd_code != '785.52')
      OR
      -- Sepsis ICD-10 codes (excluding septic shock)
      (d.icd_version = 10 AND d.icd_code IN ('R65.20', 'R65.21') AND d.icd_code != 'R65.21')
    )
),

icu_stays AS (
  -- Identify patients with ICU stays
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE
    first_careunit IN ('MICU', 'SICU', 'CCU', 'CSRU', 'TSICU')
),

ultrasound_counts AS (
  -- Count ultrasounds per admission
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS ultrasound_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE
    h.hcpcs_cd IN ('76700', '76705') -- Example ultrasound HCPCS codes
  GROUP BY
    h.subject_id, h.hadm_id
)

-- Final aggregation
SELECT
  CASE
    WHEN sp.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN sp.los_days BETWEEN 5 AND 8 THEN '5-8 days'
    ELSE 'Other'
  END AS los_category,
  CASE
    WHEN icu.subject_id IS NOT NULL THEN 'ICU'
    ELSE 'No ICU'
  END AS icu_status,
  COUNT(DISTINCT sp.hadm_id) AS patient_count,
  AVG(COALESCE(uc.ultrasound_count, 0)) AS mean_ultrasounds_per_admission
FROM
  sepsis_patients sp
LEFT JOIN
  icu_stays icu ON sp.subject_id = icu.subject_id AND sp.hadm_id = icu.hadm_id
LEFT JOIN
  ultrasound_counts uc ON sp.subject_id = uc.subject_id AND sp.hadm_id = uc.hadm_id
WHERE
  sp.los_days BETWEEN 1 AND 8
GROUP BY
  los_category, icu_status
ORDER BY
  los_category, icu_status;