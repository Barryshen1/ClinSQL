WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 48 AND 58
    AND p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code IN ('E119'))
          OR
          (d.icd_version = 9 AND d.icd_code IN ('25000'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code IN ('I509'))
          OR
          (d.icd_version = 9 AND d.icd_code IN ('4280'))
        )
    )
),

glp1_meds AS (
  SELECT *
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE
    LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%exenatide%'
),

first_72h_starts AS (
  SELECT DISTINCT c.subject_id
  FROM cohort c
  JOIN glp1_meds g
    ON c.hadm_id = g.hadm_id
  WHERE g.starttime >= c.admittime
    AND g.starttime <= c.admittime + INTERVAL 3 DAY
),

last_48h_starts AS (
  SELECT DISTINCT c.subject_id
  FROM cohort c
  JOIN glp1_meds g
    ON c.hadm_id = g.hadm_id
  WHERE g.starttime >= c.dischtime - INTERVAL 2 DAY
    AND g.starttime <= c.dischtime
)

SELECT
  ROUND(100 * COUNT(DISTINCT f.subject_id) / NULLIF(COUNT(DISTINCT c.subject_id), 0), 2) AS first_72h_initiation_rate_pct,
  ROUND(100 * COUNT(DISTINCT l.subject_id) / NULLIF(COUNT(DISTINCT c.subject_id), 0), 2) AS last_48h_initiation_rate_pct,
  ROUND(
    100 * COUNT(DISTINCT f.subject_id) / NULLIF(COUNT(DISTINCT c.subject_id), 0)
    - 100 * COUNT(DISTINCT l.subject_id) / NULLIF(COUNT(DISTINCT c.subject_id), 0),
    2
  ) AS absolute_difference_pp
FROM cohort c
LEFT JOIN first_72h_starts f ON c.subject_id = f.subject_id
LEFT JOIN last_48h_starts l ON c.subject_id = l.subject_id;