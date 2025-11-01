WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 12  -- Exclude stays <12h
),
diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%') 
    OR (icd_version = 10 AND icd_code LIKE 'E1%')
),
heart_failure AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') 
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort_conditions AS (
  SELECT c.*
  FROM cohort c
  WHERE 
    (SELECT COUNT(*) > 0 FROM diabetes d WHERE d.hadm_id = c.hadm_id)
    AND 
    (SELECT COUNT(*) > 0 FROM heart_failure hf WHERE hf.hadm_id = c.hadm_id)
),
glp1_prescriptions AS (
  SELECT 
    hadm_id,
    subject_id,
    starttime,
    LOWER(drug) AS drug_lower
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    REGEXP_CONTAINS(LOWER(drug), r'exenatide|liraglutide|dulaglutide|semaglutide|albiglutide|lixisenatide|byetta|bydureon|victoza|trulicity|ozempic|rybelsus|adlyxin')
),
cohort_flags AS (
  SELECT 
    cc.hadm_id,
    MAX(
      CASE WHEN gp.starttime 
        BETWEEN cc.admittime AND DATETIME_ADD(cc.admittime, INTERVAL 48 HOUR) 
        THEN 1 ELSE 0 
      END
    ) AS flag_first_48h,
    MAX(
      CASE WHEN gp.starttime 
        BETWEEN DATETIME_SUB(cc.dischtime, INTERVAL 12 HOUR) AND cc.dischtime 
        THEN 1 ELSE 0 
      END
    ) AS flag_final_12h
  FROM cohort_conditions cc
  LEFT JOIN glp1_prescriptions gp
    ON cc.hadm_id = gp.hadm_id
    AND cc.subject_id = gp.subject_id
  GROUP BY cc.hadm_id
)
SELECT 
  COUNT(*) AS total_admissions,
  SUM(flag_first_48h) AS count_first_48h,
  SUM(flag_final_12h) AS count_final_12h,
  ROUND(100.0 * SUM(flag_first_48h) / COUNT(*), 2) AS prevalence_first_48h_pct,
  ROUND(100.0 * SUM(flag_final_12h) / COUNT(*), 2) AS prevalence_final_12h_pct,
  ROUND(
    100.0 * SUM(flag_final_12h) / COUNT(*) - 100.0 * SUM(flag_first_48h) / COUNT(*), 
    2
  ) AS absolute_change_pct,
  ROUND(
    CASE 
      WHEN SUM(flag_first_48h) = 0 THEN NULL
      ELSE 100.0 * (
        (100.0 * SUM(flag_final_12h) / COUNT(*)) - (100.0 * SUM(flag_first_48h) / COUNT(*))
      ) / (100.0 * SUM(flag_first_48h) / COUNT(*))
    END, 
    2
  ) AS relative_change_pct
FROM cohort_flags;