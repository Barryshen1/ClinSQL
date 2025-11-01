WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in calendar days
    DATE_DIFF(CAST(adm.dischtime AS DATE), CAST(adm.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    -- Filter age 90-100 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 90 AND 100
),

los_groups AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE 'Other'
    END AS los_group
  FROM cohort
),

imaging_codes AS (
  SELECT
    icd_code,
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    -- ICD-9: Diagnostic Radiology (87, 88)
    (icd_version = 9 AND (icd_code LIKE '87%' OR icd_code LIKE '88%'))
    OR
    -- ICD-10: Imaging section (B)
    (icd_version = 10 AND icd_code LIKE 'B%')
),

procedures_per_admission AS (
  SELECT
    lg.hadm_id,
    lg.los_group,
    COUNT(DISTINCT proc.icd_code) AS num_imaging_procedures
  FROM los_groups lg
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON lg.hadm_id = proc.hadm_id
  LEFT JOIN imaging_codes img
    ON proc.icd_code = img.icd_code
    AND proc.icd_version = img.icd_version
  WHERE
    lg.los_group IN ('1-3', '4-7')  -- Only target LOS groups
  GROUP BY lg.hadm_id, lg.los_group
)

SELECT
  los_group,
  AVG(num_imaging_procedures) AS mean_procedures,
  MIN(num_imaging_procedures) AS min_procedures,
  MAX(num_imaging_procedures) AS max_procedures
FROM procedures_per_admission
GROUP BY los_group
ORDER BY los_group;