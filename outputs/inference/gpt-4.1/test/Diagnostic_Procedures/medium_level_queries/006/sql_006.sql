WITH cohort AS (
  -- Select male patients aged 48-58 at admission
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    EXTRACT(DAY FROM adm.dischtime - adm.admittime) AS los_days,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 48 AND 58
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
sepsis_admissions AS (
  -- Identify admissions with sepsis but not septic shock
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON c.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-10 sepsis codes
      (dx.icd_version = 10 AND (
        REGEXP_CONTAINS(dx.icd_code, r'^A40') OR
        REGEXP_CONTAINS(dx.icd_code, r'^A41') OR
        dx.icd_code = 'R652' -- R65.2 (sepsis, severe sepsis)
      ))
      OR
      -- ICD-9 sepsis codes
      (dx.icd_version = 9 AND (
        dx.icd_code = '99591' OR
        dx.icd_code = '99592'
      ))
    )
    -- Exclude septic shock
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx2
      WHERE dx2.hadm_id = c.hadm_id
        AND (
          (dx2.icd_version = 10 AND dx2.icd_code = 'R6521') -- R65.21 (septic shock)
          OR (dx2.icd_version = 9 AND dx2.icd_code = '78552') -- 785.52 (septic shock)
        )
    )
),
ultrasound_procs AS (
  -- Identify ultrasound procedures per admission
  SELECT
    proc.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY
    proc.hadm_id
),
icu_admissions AS (
  -- Admissions with at least one ICU stay
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),
final AS (
  -- Combine everything, assign ICU group, LOS group, and ultrasound count
  SELECT
    sa.hadm_id,
    CASE WHEN ia.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_group,
    CASE
      WHEN sa.los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN sa.los_days BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_group,
    COALESCE(up.ultrasound_count, 0) AS ultrasound_count
  FROM
    sepsis_admissions sa
    LEFT JOIN icu_admissions ia ON sa.hadm_id = ia.hadm_id
    LEFT JOIN ultrasound_procs up ON sa.hadm_id = up.hadm_id
  WHERE
    sa.los_days BETWEEN 1 AND 8
)
SELECT
  icu_group,
  los_group,
  COUNT(*) AS patient_count,
  ROUND(AVG(ultrasound_count), 2) AS mean_ultrasounds_per_admission
FROM
  final
WHERE
  los_group IS NOT NULL
GROUP BY
  icu_group,
  los_group
ORDER BY
  icu_group,
  los_group;