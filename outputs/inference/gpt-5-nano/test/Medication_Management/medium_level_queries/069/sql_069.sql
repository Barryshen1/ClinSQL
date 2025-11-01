WITH diabetes_heart_flags AS (
  -- Flag admissions that have both type 2 diabetes and heart failure
  SELECT di.subject_id, di.hadm_id,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%type 2 diabetes%' THEN 1 ELSE 0 END) AS has_diabetes_type2,
         MAX(CASE WHEN LOWER(ddi.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code
   AND di.icd_version = ddi.icd_version
  GROUP BY di.subject_id, di.hadm_id
),

cohort_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN diabetes_heart_flags AS f
    ON f.subject_id = a.subject_id
   AND f.hadm_id = a.hadm_id
  WHERE (p.gender = 'M' OR LOWER(p.gender) = 'male')
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
    AND f.has_diabetes_type2 = 1
    AND f.has_heart_failure = 1
),

glp1_overlap AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = c.subject_id
        AND pr.hadm_id = c.hadm_id
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%' OR
          LOWER(pr.drug) LIKE '%dulaglutide%' OR
          LOWER(pr.drug) LIKE '%exenatide%' OR
          LOWER(pr.drug) LIKE '%lixisenatide%' OR
          LOWER(pr.drug) LIKE '%semaglutide%' OR
          LOWER(pr.drug) LIKE '%albiglutide%'
        )
        AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
        AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
    ) AS first12h_exposed,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = c.subject_id
        AND pr.hadm_id = c.hadm_id
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%' OR
          LOWER(pr.drug) LIKE '%dulaglutide%' OR
          LOWER(pr.drug) LIKE '%exenatide%' OR
          LOWER(pr.drug) LIKE '%lixisenatide%' OR
          LOWER(pr.drug) LIKE '%semaglutide%' OR
          LOWER(pr.drug) LIKE '%albiglutide%'
        )
        AND pr.starttime < c.dischtime
        AND pr.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
    ) AS last12h_exposed
  FROM cohort_admissions AS c
)

SELECT
  COUNT(*) AS cohort_size,
  ROUND(100 * SUM(CASE WHEN first12h_exposed THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_first12h,
  ROUND(100 * SUM(CASE WHEN last12h_exposed THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_final12h,
  ROUND(
    (100 * SUM(CASE WHEN last12h_exposed THEN 1 ELSE 0 END) / COUNT(*))
    - (100 * SUM(CASE WHEN first12h_exposed THEN 1 ELSE 0 END) / COUNT(*)),
    2
  ) AS net_change
FROM glp1_overlap;