WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 56 AND 66
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '250%') OR
        (icd_version = 10 AND icd_code LIKE 'E1[0-4]%')
    )
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '428%') OR
        (icd_version = 10 AND icd_code LIKE 'I50%')
    )
),

glp1_drugs AS (
  SELECT *
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%exenatide%' OR
    LOWER(drug) LIKE '%liraglutide%' OR
    LOWER(drug) LIKE '%dulaglutide%' OR
    LOWER(drug) LIKE '%semaglutide%' OR
    LOWER(drug) LIKE '%lixisenatide%' OR
    LOWER(drug) LIKE '%albiglutide%' OR
    LOWER(drug) LIKE '%tirzepatide%'
),

cohort_with_flags AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(
      CASE 
        WHEN g.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) 
          AND (g.stoptime >= c.admittime OR g.stoptime IS NULL) 
        THEN 1 
        ELSE 0 
      END
    ) AS in_first_48h,
    MAX(
      CASE 
        WHEN g.starttime <= c.dischtime 
          AND (g.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) OR g.stoptime IS NULL) 
        THEN 1 
        ELSE 0 
      END
    ) AS in_final_24h
  FROM cohort c
  LEFT JOIN glp1_drugs g
    ON c.hadm_id = g.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)

SELECT 
  COUNT(*) AS total_admissions,
  ROUND(100.0 * SUM(in_first_48h) / COUNT(*), 2) AS prevalence_first_48h,
  ROUND(100.0 * SUM(in_final_24h) / COUNT(*), 2) AS prevalence_final_24h,
  ROUND(100.0 * SUM(in_final_24h) / COUNT(*) - 100.0 * SUM(in_first_48h) / COUNT(*), 2) AS net_change
FROM cohort_with_flags;