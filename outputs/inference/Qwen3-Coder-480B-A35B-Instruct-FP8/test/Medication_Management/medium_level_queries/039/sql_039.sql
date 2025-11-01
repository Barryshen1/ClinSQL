WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
      ON d1.icd_code = d_icd.icd_code AND d1.icd_version = d_icd.icd_version
      WHERE d1.hadm_id = a.hadm_id
        AND LOWER(d_icd.long_title) LIKE '%type 2 diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd2
      ON d2.icd_code = d_icd2.icd_code AND d2.icd_version = d_icd2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND LOWER(d_icd2.long_title) LIKE '%heart failure%'
    )
),

glp1_meds AS (
  SELECT *
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  WHERE
    LOWER(e.medication) LIKE '%semaglutide%'
    OR LOWER(e.medication) LIKE '%liraglutide%'
    OR LOWER(e.medication) LIKE '%dulaglutide%'
    OR LOWER(e.medication) LIKE '%exenatide%'
),

first_24h_admin AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN glp1_meds e ON c.hadm_id = e.hadm_id
  WHERE e.charttime >= c.intime AND e.charttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),

last_48h_admin AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN glp1_meds e ON c.hadm_id = e.hadm_id
  WHERE e.charttime >= DATETIME_SUB(c.outtime, INTERVAL 48 HOUR) AND e.charttime <= c.outtime
),

counts AS (
  SELECT
    COUNT(DISTINCT c.hadm_id) AS total,
    COUNT(DISTINCT f.hadm_id) AS first_24h_count,
    COUNT(DISTINCT l.hadm_id) AS last_48h_count
  FROM cohort c
  LEFT JOIN first_24h_admin f ON c.hadm_id = f.hadm_id
  LEFT JOIN last_48h_admin l ON c.hadm_id = l.hadm_id
)

SELECT
  total,
  first_24h_count,
  last_48h_count,
  ROUND(100 * first_24h_count / total, 2) AS first_24h_prevalence_pct,
  ROUND(100 * last_48h_count / total, 2) AS last_48h_prevalence_pct,
  (last_48h_count - first_24h_count) AS abs_change,
  ROUND(SAFE_DIVIDE((last_48h_count - first_24h_count), first_24h_count) * 100, 2) AS rel_change_pct
FROM counts;