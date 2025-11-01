WITH aki_admissions AS (
  -- Identify admissions with AKI diagnosis
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_stratum
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%acute kidney injury%'
    AND a.hadm_id IS NOT NULL
),

filtered_patients AS (
  -- Filter patients by gender and age
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 38 AND 48
),

noninvasive_procs AS (
  -- Identify non-invasive procedures
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.seq_num) AS noninvasive_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%ultrasound%'
    OR LOWER(d.long_title) LIKE '%imaging%'
    OR LOWER(d.long_title) LIKE '%ecg%'
    OR LOWER(d.long_title) LIKE '%echo%'
    OR LOWER(d.long_title) LIKE '%radiograph%'
    OR LOWER(d.long_title) LIKE '%mri%'
    OR LOWER(d.long_title) LIKE '%ct%'
  GROUP BY p.hadm_id
)

SELECT
  a.los_group,
  a.icu_stratum,
  AVG(np.noninvasive_proc_count) AS mean_diagnostics,
  MIN(np.noninvasive_proc_count) AS min_diagnostics,
  MAX(np.noninvasive_proc_count) AS max_diagnostics
FROM aki_admissions a
JOIN filtered_patients fp
  ON a.subject_id = fp.subject_id
JOIN noninvasive_procs np
  ON a.hadm_id = np.hadm_id
WHERE
  a.los_group IN ('1-4 days', '5-7 days')
GROUP BY
  a.los_group,
  a.icu_stratum
ORDER BY
  a.los_group,
  a.icu_stratum;