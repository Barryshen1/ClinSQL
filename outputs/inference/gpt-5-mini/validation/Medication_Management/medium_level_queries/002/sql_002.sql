WITH cohort AS (
  -- female inpatients age 59-69 with LOS >= 48h AND diagnoses for T2DM and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    -- T2DM diagnosis (ICD-10 E11* or ICD-9 250* or textual matches)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          d.icd_code LIKE 'E11%'        -- ICD-10 type 2 diabetes
          OR d.icd_code LIKE '250%'     -- ICD-9 diabetes codes
          OR (LOWER(dd.long_title) LIKE '%type 2%')
          OR (LOWER(dd.long_title) LIKE '%non-insulin%')
          OR (LOWER(dd.long_title) LIKE '%niddm%')
          OR (LOWER(dd.long_title) LIKE '%diabetes%')
        )
    )
    -- Heart failure diagnosis (ICD-10 I50* or ICD-9 428* or textual match)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          d.icd_code LIKE 'I50%'     -- ICD-10 heart failure
          OR d.icd_code LIKE '428%'   -- ICD-9 heart failure
          OR (LOWER(dd.long_title) LIKE '%heart failure%')
          OR (LOWER(dd.long_title) LIKE '%congestive heart failure%')
        )
    )
),

med_sources AS (
  -- prescriptions
  SELECT
    subject_id,
    hadm_id,
    starttime AS med_start,
    COALESCE(stoptime, starttime) AS med_end,
    drug AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`

  UNION ALL

  -- pharmacy (dispense / administration records)
  SELECT
    subject_id,
    hadm_id,
    starttime AS med_start,
    COALESCE(stoptime, starttime) AS med_end,
    medication AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`

  UNION ALL

  -- emar (administration events)
  SELECT
    subject_id,
    hadm_id,
    charttime AS med_start,
    charttime AS med_end,
    medication AS med_text
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
),

glp_meds AS (
  -- Filter to likely injectable GLP-1 receptor agonists by medication text.
  -- Exclude obvious oral formulations (e.g., 'rybelsus' or 'oral').
  SELECT
    ms.*
  FROM med_sources ms
  WHERE (
      LOWER(ms.med_text) LIKE '%liraglutide%'
      OR LOWER(ms.med_text) LIKE '%dulaglutide%'
      OR LOWER(ms.med_text) LIKE '%semaglutide%'
      OR LOWER(ms.med_text) LIKE '%exenatide%'
      OR LOWER(ms.med_text) LIKE '%lixisenatide%'
      OR LOWER(ms.med_text) LIKE '%albiglutide%'
      -- brand names
      OR LOWER(ms.med_text) LIKE '%victoza%'
      OR LOWER(ms.med_text) LIKE '%trulicity%'
      OR LOWER(ms.med_text) LIKE '%ozempic%'
      OR LOWER(ms.med_text) LIKE '%byetta%'
      OR LOWER(ms.med_text) LIKE '%bydureon%'
      OR LOWER(ms.med_text) LIKE '%adlyxin%'
    )
    AND LOWER(ms.med_text) NOT LIKE '%oral%'
    AND LOWER(ms.med_text) NOT LIKE '%rybelsus%'
),

per_admission AS (
  -- For each admission in cohort, determine if there was any GLP-1 use in first 48h and in final 12h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MAX(CASE
          WHEN g.med_start < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
           AND g.med_end >= c.admittime
          THEN 1 ELSE 0 END) AS any_glp_first48,
    MAX(CASE
          WHEN g.med_start < c.dischtime
           AND g.med_end >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
          THEN 1 ELSE 0 END) AS any_glp_final12
  FROM cohort c
  LEFT JOIN glp_meds g
    ON c.hadm_id = g.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime
)

SELECT
  COUNT(*) AS cohort_n,
  SUM(any_glp_first48) AS n_glp_first48,
  ROUND( SAFE_DIVIDE(SUM(any_glp_first48), COUNT(*)) * 100, 2) AS pct_glp_first48,
  SUM(any_glp_final12) AS n_glp_final12,
  ROUND( SAFE_DIVIDE(SUM(any_glp_final12), COUNT(*)) * 100, 2) AS pct_glp_final12,
  ROUND( ABS(
        SAFE_DIVIDE(SUM(any_glp_first48), COUNT(*)) * 100
      - SAFE_DIVIDE(SUM(any_glp_final12), COUNT(*)) * 100
    ), 2) AS absolute_percentage_point_difference
FROM per_admission;