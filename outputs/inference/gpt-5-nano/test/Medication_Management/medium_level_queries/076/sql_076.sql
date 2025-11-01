WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE (
        UPPER(COALESCE(p.gender, '')) IN ('F', 'FEMALE')
      )
    AND p.anchor_age BETWEEN 75 AND 85
    -- at least 36 hours inpatient stay
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 36
    -- has diabetes diagnosis (ICD-9: 250x/251x; ICD-10: E10x/E11x)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND (di.icd_code LIKE '250%' OR di.icd_code LIKE '251%'))
          OR
          (di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%'))
        )
    )
    -- and acute heart failure diagnosis (ICD-9: 428x; ICD-10: I50x)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '428%')
          OR
          (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
        )
    )
),
glp1_flags AS (
  SELECT
    c.hadm_id,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      WHERE pr.subject_id = c.subject_id
        AND pr.hadm_id = c.hadm_id
        AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%' OR
          LOWER(pr.drug) LIKE '%exenatide%' OR
          LOWER(pr.drug) LIKE '%dulaglutide%' OR
          LOWER(pr.drug) LIKE '%lixisenatide%' OR
          LOWER(pr.drug) LIKE '%albiglutide%' OR
          LOWER(pr.drug) LIKE '%semaglutide%'
        )
        AND (pr.route IS NULL OR LOWER(pr.route) LIKE '%subcutaneous%' OR LOWER(pr.route) LIKE '%sc%')
    ) AS glp1_first24,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      WHERE pr.subject_id = c.subject_id
        AND pr.hadm_id = c.hadm_id
        AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%' OR
          LOWER(pr.drug) LIKE '%exenatide%' OR
          LOWER(pr.drug) LIKE '%dulaglutide%' OR
          LOWER(pr.drug) LIKE '%lixisenatide%' OR
          LOWER(pr.drug) LIKE '%albiglutide%' OR
          LOWER(pr.drug) LIKE '%semaglutide%'
        )
        AND (pr.route IS NULL OR LOWER(pr.route) LIKE '%subcutaneous%' OR LOWER(pr.route) LIKE '%sc%')
    ) AS glp1_final12
  FROM cohort c
)
SELECT
  ROUND(100.0 * SUM(IF(glp1_first24, 1, 0)) / COUNT(*), 2) AS pct_glp1_started_in_first_24h,
  ROUND(100.0 * SUM(IF(glp1_final12, 1, 0)) / COUNT(*), 2) AS pct_glp1_started_in_final_12h
FROM glp1_flags;