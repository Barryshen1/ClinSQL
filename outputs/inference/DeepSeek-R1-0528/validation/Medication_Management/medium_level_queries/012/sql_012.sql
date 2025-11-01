WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    -- Calculate end_time as min(dischtime or 72h post-admission)
    CASE 
      WHEN DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR) <= adm.dischtime 
        THEN DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
      ELSE adm.dischtime 
    END AS end_time
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 50 AND 60
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 72
    -- Type 2 diabetes
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.subject_id = adm.subject_id 
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '250.%' AND (diag.icd_code LIKE '%0' OR diag.icd_code LIKE '%2'))
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%')
        )
    )
    -- Heart failure
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.subject_id = adm.subject_id 
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
          OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I50%' OR diag.icd_code IN ('I11.0', 'I13.0', 'I13.2')))
        )
    )
),
cohort_with_flags AS (
  SELECT 
    c.*,
    -- Flag for GLP-1 initiation in first 12h
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.emar` e
      WHERE 
        e.subject_id = c.subject_id 
        AND e.hadm_id = c.hadm_id
        AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
        AND (
          LOWER(e.medication) LIKE '%exenatide%' OR LOWER(e.medication) LIKE '%liraglutide%' 
          OR LOWER(e.medication) LIKE '%dulaglutide%' OR LOWER(e.medication) LIKE '%semaglutide%' 
          OR LOWER(e.medication) LIKE '%albiglutide%' OR LOWER(e.medication) LIKE '%lixisenatide%'
          OR LOWER(e.medication) LIKE '%byetta%' OR LOWER(e.medication) LIKE '%bydureon%' 
          OR LOWER(e.medication) LIKE '%victoza%' OR LOWER(e.medication) LIKE '%saxenda%' 
          OR LOWER(e.medication) LIKE '%trulicity%' OR LOWER(e.medication) LIKE '%ozempic%' 
          OR LOWER(e.medication) LIKE '%rybelsus%' OR LOWER(e.medication) LIKE '%wegovy%' 
          OR LOWER(e.medication) LIKE '%tanzeum%' OR LOWER(e.medication) LIKE '%adlyxin%'
        )
    ) THEN 1 ELSE 0 END AS initiated,
    -- Flag for GLP-1 prevalence at end_time
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      WHERE 
        p.subject_id = c.subject_id 
        AND p.hadm_id = c.hadm_id
        AND p.starttime <= c.end_time
        AND (p.stoptime IS NULL OR p.stoptime >= c.end_time)
        AND (
          LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%' 
          OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' 
          OR LOWER(p.drug) LIKE '%albiglutide%' OR LOWER(p.drug) LIKE '%lixisenatide%'
          OR LOWER(p.drug) LIKE '%byetta%' OR LOWER(p.drug) LIKE '%bydureon%' 
          OR LOWER(p.drug) LIKE '%victoza%' OR LOWER(p.drug) LIKE '%saxenda%' 
          OR LOWER(p.drug) LIKE '%trulicity%' OR LOWER(p.drug) LIKE '%ozempic%' 
          OR LOWER(p.drug) LIKE '%rybelsus%' OR LOWER(p.drug) LIKE '%wegovy%' 
          OR LOWER(p.drug) LIKE '%tanzeum%' OR LOWER(p.drug) LIKE '%adlyxin%'
        )
    ) THEN 1 ELSE 0 END AS prevalent
  FROM cohort c
)
SELECT 
  COUNT(*) AS total_admissions,
  ROUND(SUM(initiated) * 100.0 / COUNT(*), 2) AS first_12h_initiation_percent,
  ROUND(SUM(prevalent) * 100.0 / COUNT(*), 2) AS final_72h_prevalence_percent,
  ROUND(
    (SUM(prevalent) * 100.0 / COUNT(*)) - (SUM(initiated) * 100.0 / COUNT(*)), 
    2
  ) AS net_percentage_point_change
FROM cohort_with_flags;