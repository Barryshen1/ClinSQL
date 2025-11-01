WITH
  ultrasound_events AS (
    -- ICD-coded procedures (e.g., from billing)
    SELECT
      proc.subject_id,
      proc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
      ON proc.icd_code = d_proc.icd_code
      AND proc.icd_version = d_proc.icd_version
    WHERE
      LOWER(d_proc.long_title) LIKE '%ultrasound%'
      OR LOWER(d_proc.long_title) LIKE '%echocardiogra%'

    UNION ALL

    -- HCPCS-coded procedures
    SELECT
      hcpcs.subject_id,
      hcpcs.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hcpcs
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d_hcpcs
      ON hcpcs.hcpcs_cd = d_hcpcs.code
    WHERE
      LOWER(d_hcpcs.long_description) LIKE '%ultrasound%'
      OR LOWER(d_hcpcs.long_description) LIKE '%echocardiogra%'

    UNION ALL

    -- ICU-specific procedures
    SELECT
      pe.subject_id,
      pe.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON pe.itemid = di.itemid
    WHERE
      (
        LOWER(di.label) LIKE '%ultrasound%'
        OR LOWER(di.label) LIKE '%echo%'
      )
      -- Filter to categories that represent the procedure itself, not a derived measurement
      AND di.category IN ('Procedures', 'Imaging')
  ),

  ultrasound_counts_per_admission AS (
    SELECT
      hadm_id,
      COUNT(*) AS ultrasound_count
    FROM ultrasound_events
    GROUP BY
      hadm_id
  ),

  cohort AS (
    SELECT
      adm.hadm_id,
      -- Stratify by admission type
      CASE
        WHEN adm.admission_type = 'ELECTIVE'
          THEN 'Elective'
        ELSE 'ED'
      END AS admission_category,
      -- Stratify by length of stay
      CASE
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3
          THEN '1-3 days'
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7
          THEN '4-7 days'
      END AS los_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 73 AND 83
      -- Filter to only the admission types and LOS groups of interest
      AND adm.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
      AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
  )

SELECT
  c.admission_category,
  c.los_category,
  AVG(COALESCE(uc.ultrasound_count, 0)) AS mean_ultrasounds,
  MIN(COALESCE(uc.ultrasound_count, 0)) AS min_ultrasounds,
  MAX(COALESCE(uc.ultrasound_count, 0)) AS max_ultrasounds
FROM cohort AS c
LEFT JOIN ultrasound_counts_per_admission AS uc
  ON c.hadm_id = uc.hadm_id
GROUP BY
  c.admission_category,
  c.los_category
ORDER BY
  c.admission_category,
  c.los_category;