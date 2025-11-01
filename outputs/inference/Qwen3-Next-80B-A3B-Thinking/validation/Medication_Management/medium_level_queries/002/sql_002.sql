WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.dischtime - a.admittime >= INTERVAL '48 HOUR'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'E11%' 
        AND d.icd_version = 10
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'I50%' 
        AND d.icd_version = 10
    )
),
glp1_flags AS (
  SELECT 
    c.subject_id,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.emar` e 
      WHERE e.subject_id = c.subject_id 
        AND e.hadm_id = c.hadm_id 
        AND e.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '48 HOUR'
        AND (
          LOWER(e.medication) LIKE '%exenatide%' 
          OR LOWER(e.medication) LIKE '%byetta%' 
          OR LOWER(e.medication) LIKE '%bydureon%' 
          OR LOWER(e.medication) LIKE '%liraglutide%' 
          OR LOWER(e.medication) LIKE '%victoza%' 
          OR LOWER(e.medication) LIKE '%semaglutide%' 
          OR LOWER(e.medication) LIKE '%ozempic%' 
          OR LOWER(e.medication) LIKE '%dulaglutide%' 
          OR LOWER(e.medication) LIKE '%trulicity%' 
          OR LOWER(e.medication) LIKE '%albiglutide%' 
          OR LOWER(e.medication) LIKE '%tanzeum%'
        )
    ) AS first_48h,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.emar` e 
      WHERE e.subject_id = c.subject_id 
        AND e.hadm_id = c.hadm_id 
        AND e.charttime BETWEEN c.dischtime - INTERVAL '12 HOUR' AND c.dischtime
        AND (
          LOWER(e.medication) LIKE '%exenatide%' 
          OR LOWER(e.medication) LIKE '%byetta%' 
          OR LOWER(e.medication) LIKE '%bydureon%' 
          OR LOWER(e.medication) LIKE '%liraglutide%' 
          OR LOWER(e.medication) LIKE '%victoza%' 
          OR LOWER(e.medication) LIKE '%semaglutide%' 
          OR LOWER(e.medication) LIKE '%ozempic%' 
          OR LOWER(e.medication) LIKE '%dulaglutide%' 
          OR LOWER(e.medication) LIKE '%trulicity%' 
          OR LOWER(e.medication) LIKE '%albiglutide%' 
          OR LOWER(e.medication) LIKE '%tanzeum%'
        )
    ) AS final_12h
  FROM cohort c
)
SELECT 
  AVG(first_48h) * 100 AS first_48h_prevalence,
  AVG(final_12h) * 100 AS final_12h_prevalence,
  ABS(AVG(first_48h) - AVG(final_12h)) * 100 AS absolute_pp_difference
FROM glp1_flags;