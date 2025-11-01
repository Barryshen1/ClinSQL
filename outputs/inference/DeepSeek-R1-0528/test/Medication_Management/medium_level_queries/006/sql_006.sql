WITH t2dm_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250\.[0-9]{1,2}[02]')) OR
    (icd_version = 10 AND icd_code LIKE 'E11%')
),
hf_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') OR
    (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
),
cohort_diag AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime
  FROM cohort c
  WHERE c.age_at_admit BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      JOIN t2dm_codes t2dm 
        ON diag.icd_code = t2dm.icd_code AND diag.icd_version = t2dm.icd_version
      WHERE diag.hadm_id = c.hadm_id
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      JOIN hf_codes hf 
        ON diag.icd_code = hf.icd_code AND diag.icd_version = hf.icd_version
      WHERE diag.hadm_id = c.hadm_id
    )
),
glp1_events AS (
  SELECT 
    emar.hadm_id,
    emar.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` emar
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON emar.emar_id = ed.emar_id AND emar.emar_seq = ed.emar_seq
  WHERE 
    (LOWER(emar.medication) LIKE '%exenatide%' OR 
     LOWER(emar.medication) LIKE '%liraglutide%' OR 
     LOWER(emar.medication) LIKE '%dulaglutide%' OR 
     LOWER(emar.medication) LIKE '%semaglutide%' OR 
     LOWER(emar.medication) LIKE '%lixisenatide%')
    AND LOWER(ed.route) LIKE '%subq%'
),
cohort_glp1 AS (
  SELECT 
    cd.hadm_id,
    cd.admittime,
    cd.dischtime,
    MAX(CASE 
          WHEN g.charttime BETWEEN cd.admittime AND 
               DATETIME_ADD(cd.admittime, INTERVAL 72 HOUR) 
               THEN 1 
          ELSE 0 
        END) AS in_first_72h,
    MAX(CASE 
          WHEN g.charttime BETWEEN 
               DATETIME_SUB(cd.dischtime, INTERVAL 48 HOUR) AND cd.dischtime 
               THEN 1 
          ELSE 0 
        END) AS in_last_48h
  FROM cohort_diag cd
  LEFT JOIN glp1_events g
    ON cd.hadm_id = g.hadm_id
  GROUP BY cd.hadm_id, cd.admittime, cd.dischtime
)
SELECT 
  COUNT(*) AS total_admissions,
  SUM(in_first_72h) AS count_first_72h,
  SUM(in_last_48h) AS count_last_48h,
  ROUND(100.0 * SUM(in_first_72h) / COUNT(*), 2) AS rate_first_72h,
  ROUND(100.0 * SUM(in_last_48h) / COUNT(*), 2) AS rate_last_48h,
  ROUND(
    100.0 * SUM(in_first_72h) / COUNT(*) - 
    100.0 * SUM(in_last_48h) / COUNT(*), 
    2
  ) AS rate_diff_pp
FROM cohort_glp1;