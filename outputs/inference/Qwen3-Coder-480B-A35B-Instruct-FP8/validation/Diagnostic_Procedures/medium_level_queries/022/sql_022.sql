WITH hf_admissions AS (
  -- Identify admissions with heart failure diagnosis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%heart failure%'
),

female_patients AS (
  -- Filter for 74-year-old females
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age = 74
),

first_icu_stays AS (
  -- Get first ICU stay per admission
  SELECT
    stay_id,
    hadm_id,
    intime,
    outtime,
    DATE_DIFF(outtime, intime, DAY) AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) = 1
),

los_groups AS (
  -- Categorize ICU LOS
  SELECT
    hadm_id,
    CASE
      WHEN icu_los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN icu_los BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_group
  FROM first_icu_stays
  WHERE icu_los BETWEEN 1 AND 7
),

admission_types AS (
  -- Classify admission type
  SELECT
    hadm_id,
    CASE
      WHEN admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent'
      WHEN admission_type = 'ELECTIVE' THEN 'Elective'
      ELSE NULL
    END AS adm_type
  FROM hf_admissions
),

noninvasive_procs AS (
  -- Identify non-invasive diagnostic procedures
  SELECT
    p.hadm_id,
    COUNT(*) AS proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    REGEXP_CONTAINS(LOWER(dp.long_title), r'(ecg|eeg|pulmonary function|imaging|scan|ct|mri)')
    AND LOWER(dp.long_title) NOT LIKE '%invasive%'
  GROUP BY p.hadm_id
)

-- Final aggregation
SELECT
  lg.los_group,
  `at`.adm_type,
  AVG(COALESCE(np.proc_count, 0)) AS mean_diagnostics_per_admission
FROM
  hf_admissions ha
JOIN
  female_patients fp ON ha.subject_id = fp.subject_id
JOIN
  los_groups lg ON ha.hadm_id = lg.hadm_id
JOIN
  admission_types `at` ON ha.hadm_id = `at`.hadm_id
LEFT JOIN
  noninvasive_procs np ON ha.hadm_id = np.hadm_id
GROUP BY
  lg.los_group,
  `at`.adm_type
ORDER BY
  lg.los_group,
  `at`.adm_type;