WITH bleed_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE (
    (di.icd_version = 9 AND di.icd_code IN ('569.3', '562.12', '569.84')) OR
    (di.icd_version = 10 AND di.icd_code IN ('K62.5', 'K57.81', 'K57.91'))
  )
),
diagnostics_count AS (
  SELECT pi.hadm_id, COUNT(*) AS num_diag
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%x-ray%'
     OR LOWER(dip.long_title) LIKE '%tomography%'
     OR LOWER(dip.long_title) LIKE '%magnetic resonance%'
     OR LOWER(dip.long_title) LIKE '%ultrasound%'
     OR LOWER(dip.long_title) LIKE '%ecg%'
     OR LOWER(dip.long_title) LIKE '%ekg%'
     OR LOWER(dip.long_title) LIKE '%eeg%'
     OR LOWER(dip.long_title) LIKE '%pulmonary function%'
     OR LOWER(dip.long_title) LIKE '%spirometry%'
  GROUP BY pi.hadm_id
)
SELECT
  los_group,
  icu_status,
  COUNT(*) AS num_admissions,
  ROUND(AVG(COALESCE(dc.num_diag, 0)), 2) AS mean_num_diagnostics
FROM (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN bleed_admissions ba
    ON a.hadm_id = ba.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 62 AND 72
    AND a.dischtime > a.admittime
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
) admissions_filtered
LEFT JOIN diagnostics_count dc
  ON admissions_filtered.hadm_id = dc.hadm_id
WHERE los_group IS NOT NULL
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;