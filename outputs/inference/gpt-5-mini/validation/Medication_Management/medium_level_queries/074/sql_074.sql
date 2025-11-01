WITH cohort AS (
  -- Female inpatients aged 48-58 with diabetes AND heart failure
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
    USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.hadm_id IS NOT NULL
    AND a.dischtime IS NOT NULL  -- needed for final 12h window
    -- must have a diagnosis of diabetes for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code
        AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%diabetes%'
    )
    -- must have a diagnosis of heart failure for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2
        ON di2.icd_code = d2.icd_code
        AND di2.icd_version = d2.icd_version
      WHERE di2.hadm_id = a.hadm_id
        AND LOWER(d2.long_title) LIKE '%heart failure%'
    )
),

glp1_meds AS (
  -- union medication starts from prescriptions and pharmacy tables
  SELECT
    hadm_id,
    starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    hadm_id IS NOT NULL
    AND starttime IS NOT NULL
    AND (
      -- name-based GLP-1 detection
      REGEXP_CONTAINS(LOWER(COALESCE(drug, '')), r'(liraglutide|exenatide|semaglutide|dulaglutide|lixisenatide|albiglutide|efpeglenatide|taspoglutide)')
      -- OR route explicitly indicates subcutaneous (rarely needed if name match is present)
      OR LOWER(COALESCE(route, '')) LIKE '%subcut%'
      OR LOWER(COALESCE(route, '')) IN ('sc', 'sq', 's.c.')
    )

  UNION ALL

  SELECT
    hadm_id,
    starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE
    hadm_id IS NOT NULL
    AND starttime IS NOT NULL
    AND (
      REGEXP_CONTAINS(LOWER(COALESCE(medication, '')), r'(liraglutide|exenatide|semaglutide|dulaglutide|lixisenatide|albiglutide|efpeglenatide|taspoglutide)')
      OR LOWER(COALESCE(route, '')) LIKE '%subcut%'
      OR LOWER(COALESCE(route, '')) IN ('sc', 'sq', 's.c.')
    )
),

-- For each admission in the cohort, determine whether there was >=1 GLP-1 start in the windows
adm_med_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- indicator: any GLP-1 start in first 24 hours after admittime
    MAX(CASE WHEN m.starttime >= c.admittime
                  AND m.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
             THEN 1 ELSE 0 END) AS glp1_first24_flag,
    -- indicator: any GLP-1 start in final 12 hours before dischtime
    MAX(CASE WHEN m.starttime <= c.dischtime
                  AND m.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS glp1_final12_flag
  FROM
    cohort c
  LEFT JOIN
    glp1_meds m
    ON c.hadm_id = m.hadm_id
      -- also ensure med start falls within admission boundaries
      AND m.starttime >= c.admittime
      AND m.starttime <= c.dischtime
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime
)

SELECT
  COUNT(1) AS total_admissions,
  SUM(glp1_first24_flag) AS admissions_with_glp1_first24,
  ROUND(100.0 * SUM(glp1_first24_flag) / COUNT(1), 2) AS pct_glp1_first24,
  SUM(glp1_final12_flag) AS admissions_with_glp1_final12,
  ROUND(100.0 * SUM(glp1_final12_flag) / COUNT(1), 2) AS pct_glp1_final12
FROM
  adm_med_flags;