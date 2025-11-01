WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON a.subject_id = di.subject_id
      AND a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND (
      LOWER(dd.long_title) LIKE '%lower gastrointestinal%'
      OR LOWER(dd.long_title) LIKE '%lower gi bleed%'
    )
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
  GROUP BY
    p.subject_id,
    a.hadm_id,
    los_days
),

icu_flag AS (
  SELECT
    hadm_id,
    CASE
      WHEN COUNT(*) > 0 THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY
    hadm_id
),

diag_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_diag
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE
    -- common imaging, ECG/EEG, PFT keywords
    LOWER(h.short_description) LIKE '%ct%'
    OR LOWER(h.short_description) LIKE '%mri%'
    OR LOWER(h.short_description) LIKE '%xray%'
    OR LOWER(h.short_description) LIKE '%ultrasound%'
    OR LOWER(h.short_description) LIKE '%ecg%'
    OR LOWER(h.short_description) LIKE '%ekg%'
    OR LOWER(h.short_description) LIKE '%eeg%'
    OR LOWER(h.short_description) LIKE '%pft%'
    OR LOWER(h.short_description) LIKE '%spirometry%'
  GROUP BY
    hadm_id
)

SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
  END AS los_group,
  COALESCE(i.icu_status, 'No ICU') AS icu_status,
  ROUND(AVG(COALESCE(d.num_diag, 0)), 2) AS mean_noninv_diags
FROM
  cohort c
  LEFT JOIN icu_flag i
    ON c.hadm_id = i.hadm_id
  LEFT JOIN diag_counts d
    ON c.hadm_id = d.hadm_id
GROUP BY
  los_group,
  icu_status
ORDER BY
  los_group,
  icu_status;