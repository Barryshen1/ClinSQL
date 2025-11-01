WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  -- Age & gender filter
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
),
t2dm_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE ( (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%')
       OR (diag.icd_version = 9 AND diag.icd_code LIKE '250%' AND 
            RIGHT(diag.icd_code,2) IN ('00','02','10','12','20','22','30','32','40','42','50','52','60','62','70','72','80','82','90','92') )
        )
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE ( (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
       OR (diag.icd_version = 9 AND diag.icd_code LIKE '428%') )
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN t2dm_hadm t ON c.hadm_id = t.hadm_id
  JOIN hf_hadm h ON c.hadm_id = h.hadm_id
),
glp1_first_final AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN LOWER(pres.drug) LIKE '%liraglutide%' 
               OR LOWER(pres.drug) LIKE '%semaglutide%'
               OR LOWER(pres.drug) LIKE '%dulaglutide%'
               OR LOWER(pres.drug) LIKE '%exenatide%'
               OR LOWER(pres.drug) LIKE '%albiglutide%'
               THEN CASE WHEN pres.route IS NULL 
                         OR LOWER(pres.route) LIKE '%subcut%' 
                         OR LOWER(pres.route) LIKE '%sc%' 
                         THEN CASE WHEN pres.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
                                   THEN 1 ELSE 0 END
                         ELSE 0 END
               ELSE 0 END) AS glp1_first24_flag,
    MAX(CASE WHEN LOWER(pres.drug) LIKE '%liraglutide%' 
               OR LOWER(pres.drug) LIKE '%semaglutide%'
               OR LOWER(pres.drug) LIKE '%dulaglutide%'
               OR LOWER(pres.drug) LIKE '%exenatide%'
               OR LOWER(pres.drug) LIKE '%albiglutide%'
               THEN CASE WHEN pres.route IS NULL 
                         OR LOWER(pres.route) LIKE '%subcut%' 
                         OR LOWER(pres.route) LIKE '%sc%' 
                         THEN CASE WHEN pres.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
                                   THEN 1 ELSE 0 END
                         ELSE 0 END
               ELSE 0 END) AS glp1_final48_flag
  FROM cohort_with_dx c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.hadm_id = pres.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
agg AS (
  SELECT
    COUNT(*) AS total_n,
    SUM(glp1_first24_flag) AS first24_n,
    SUM(glp1_final48_flag) AS final48_n
  FROM glp1_first_final
)
SELECT
  total_n,
  first24_n,
  final48_n,
  ROUND(100.0 * first24_n / total_n, 2) AS first24_pct,
  ROUND(100.0 * final48_n / total_n, 2) AS final48_pct,
  ROUND( (100.0 * final48_n / total_n) - (100.0 * first24_n / total_n), 2) AS absolute_change_pct,
  ROUND( (( (100.0 * final48_n / total_n) - (100.0 * first24_n / total_n) ) / (100.0 * first24_n / total_n) ) * 100.0 , 2) AS relative_change_pct
FROM agg;