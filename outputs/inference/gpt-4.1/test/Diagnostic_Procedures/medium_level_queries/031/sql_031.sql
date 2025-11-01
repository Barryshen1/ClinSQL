WITH aki_admissions AS (
  -- Identify AKI admissions for females age 38-48
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
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
      ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
    AND (
      -- ICD-10 AKI codes
      (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
      -- ICD-9 AKI codes
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
    )
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
aki_admissions_with_bins AS (
  -- Add stay duration bins and ICU use
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_days,
    CASE
      WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN a.los_days BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS stay_bin,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_use
  FROM aki_admissions a
  WHERE a.los_days BETWEEN 1 AND 7
),
diagnostic_counts AS (
  -- Count non-invasive diagnostics per admission
  SELECT
    ab.subject_id,
    ab.hadm_id,
    ab.stay_bin,
    ab.icu_use,
    -- Count unique labs
    IFNULL(lab.lab_count, 0) AS lab_count,
    -- Count unique microbiology events
    IFNULL(micro.micro_count, 0) AS micro_count,
    -- Total non-invasive diagnostics
    IFNULL(lab.lab_count, 0) + IFNULL(micro.micro_count, 0) AS total_diagnostics
  FROM aki_admissions_with_bins ab
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT labevent_id) AS lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    GROUP BY hadm_id
  ) lab
    ON ab.hadm_id = lab.hadm_id
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT microevent_id) AS micro_count
    FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents`
    GROUP BY hadm_id
  ) micro
    ON ab.hadm_id = micro.hadm_id
)
SELECT
  icu_use,
  stay_bin,
  COUNT(*) AS admission_count,
  AVG(total_diagnostics) AS mean_diagnostics,
  MIN(total_diagnostics) AS min_diagnostics,
  MAX(total_diagnostics) AS max_diagnostics
FROM diagnostic_counts
WHERE stay_bin IS NOT NULL
GROUP BY icu_use, stay_bin
ORDER BY icu_use, stay_bin;