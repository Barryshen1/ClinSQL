WITH
  PatientCohort AS (
    SELECT DISTINCT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON adm.subject_id = p.subject_id
    WHERE
      p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 50 AND 60
      AND adm.admittime IS NOT NULL
      AND adm.dischtime IS NOT NULL -- Exclude ongoing admissions as final 72h window requires dischtime
      -- Filter for diabetes diagnosis
      AND EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_dm
        WHERE
          diag_dm.subject_id = adm.subject_id
          AND diag_dm.hadm_id = adm.hadm_id
          AND (
            (diag_dm.icd_version = 9 AND diag_dm.icd_code LIKE '250%') -- ICD-9 diabetes
            OR (diag_dm.icd_version = 10 AND (diag_dm.icd_code LIKE 'E10%' OR diag_dm.icd_code LIKE 'E11%' OR diag_dm.icd_code LIKE 'E13%')) -- ICD-10 diabetes
          )
      )
      -- Filter for heart failure diagnosis
      AND EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_hf
        WHERE
          diag_hf.subject_id = adm.subject_id
          AND diag_hf.hadm_id = adm.hadm_id
          AND (
            (diag_hf.icd_version = 9 AND diag_hf.icd_code LIKE '428%') -- ICD-9 heart failure
            OR (diag_hf.icd_version = 10 AND diag_hf.icd_code LIKE 'I50%') -- ICD-10 heart failure
          )
      )
  ),
  -- Step 2: Identify the first injectable GLP-1 prescription time for each admission
  GLP1Initiations AS (
    SELECT
      p.subject_id,
      p.hadm_id,
      MIN(p.starttime) AS first_glp1_starttime
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    WHERE
      (
        LOWER(p.drug) LIKE '%semaglutide%'
        OR LOWER(p.drug) LIKE '%liraglutide%'
        OR LOWER(p.drug) LIKE '%dulaglutide%'
        OR LOWER(p.drug) LIKE '%exenatide%'
        OR LOWER(p.drug) LIKE '%lixisenatide%'
      )
      -- Filtering by common injectable routes to ensure "injectable GLP-1s" per prompt
      AND UPPER(p.route) IN ('SUBCUTANEOUS', 'INTRAVENOUS', 'INTRAMUSCULAR', 'SC', 'IV', 'IM')
      AND p.starttime IS NOT NULL
    GROUP BY
      p.subject_id, p.hadm_id
  )
SELECT
  -- Count total admissions in the cohort
  COUNT(DISTINCT pc.hadm_id) AS total_cohort_admissions,

  -- Count initiations in the first 72 hours
  COUNT(
    DISTINCT CASE
      WHEN glp1.first_glp1_starttime >= pc.admittime
      AND glp1.first_glp1_starttime <= DATETIME_ADD(pc.admittime, INTERVAL 72 HOUR) THEN pc.hadm_id
      ELSE NULL
    END
  ) AS initiated_first_72h,

  -- Count initiations in the final 72 hours
  COUNT(
    DISTINCT CASE
      WHEN glp1.first_glp1_starttime >= DATETIME_SUB(pc.dischtime, INTERVAL 72 HOUR)
      AND glp1.first_glp1_starttime <= pc.dischtime THEN pc.hadm_id
      ELSE NULL
    END
  ) AS initiated_final_72h,

  -- Calculate the rate for the first 72 hours
  SAFE_DIVIDE(
    COUNT(
      DISTINCT CASE
        WHEN glp1.first_glp1_starttime >= pc.admittime
        AND glp1.first_glp1_starttime <= DATETIME_ADD(pc.admittime, INTERVAL 72 HOUR) THEN pc.hadm_id
        ELSE NULL
      END
    ) * 100.0,
    COUNT(DISTINCT pc.hadm_id)
  ) AS rate_first_72h_percent,

  -- Calculate the rate for the final 72 hours
  SAFE_DIVIDE(
    COUNT(
      DISTINCT CASE
        WHEN glp1.first_glp1_starttime >= DATETIME_SUB(pc.dischtime, INTERVAL 72 HOUR)
        AND glp1.first_glp1_starttime <= pc.dischtime THEN pc.hadm_id
        ELSE NULL
      END
    ) * 100.0,
    COUNT(DISTINCT pc.hadm_id)
  ) AS rate_final_72h_percent,

  -- Calculate the absolute change in rates
  (
    SAFE_DIVIDE(
      COUNT(
        DISTINCT CASE
          WHEN glp1.first_glp1_starttime >= DATETIME_SUB(pc.dischtime, INTERVAL 72 HOUR)
          AND glp1.first_glp1_starttime <= pc.dischtime THEN pc.hadm_id
          ELSE NULL
        END
      ) * 100.0,
      COUNT(DISTINCT pc.hadm_id)
    )
    -
    SAFE_DIVIDE(
      COUNT(
        DISTINCT CASE
          WHEN glp1.first_glp1_starttime >= pc.admittime
          AND glp1.first_glp1_starttime <= DATETIME_ADD(pc.admittime, INTERVAL 72 HOUR) THEN pc.hadm_id
          ELSE NULL
        END
      ) * 100.0,
      COUNT(DISTINCT pc.hadm_id)
    )
  ) AS absolute_change_percent,

  -- Calculate the relative change in rates (as a percentage difference of the first 72h rate)
  SAFE_DIVIDE(
    (
      SAFE_DIVIDE(
        COUNT(
          DISTINCT CASE
            WHEN glp1.first_glp1_starttime >= DATETIME_SUB(pc.dischtime, INTERVAL 72 HOUR)
            AND glp1.first_glp1_starttime <= pc.dischtime THEN pc.hadm_id
            ELSE NULL
          END
        ) * 100.0,
        COUNT(DISTINCT pc.hadm_id)
      )
      -
      SAFE_DIVIDE(
        COUNT(
          DISTINCT CASE
            WHEN glp1.first_glp1_starttime >= pc.admittime
            AND glp1.first_glp1_starttime <= DATETIME_ADD(pc.admittime, INTERVAL 72 HOUR) THEN pc.hadm_id
            ELSE NULL
          END
        ) * 100.0,
        COUNT(DISTINCT pc.hadm_id)
      )
    ) * 100.0, -- Multiply by 100 to express relative change as a percentage
    SAFE_DIVIDE(
      COUNT(
        DISTINCT CASE
          WHEN glp1.first_glp1_starttime >= pc.admittime
          AND glp1.first_glp1_starttime <= DATETIME_ADD(pc.admittime, INTERVAL 72 HOUR) THEN pc.hadm_id
          ELSE NULL
        END
      ) * 100.0,
      COUNT(DISTINCT pc.hadm_id)
    )
  ) AS relative_change_rate_of_first_72h_percent
FROM
  PatientCohort AS pc
LEFT JOIN
  GLP1Initiations AS glp1
  ON pc.subject_id = glp1.subject_id AND pc.hadm_id = glp1.hadm_id;