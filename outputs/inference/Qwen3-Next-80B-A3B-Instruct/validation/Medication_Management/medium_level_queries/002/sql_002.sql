WITH eligible_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1
    ON i.subject_id = d1.subject_id AND i.hadm_id = d1.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2
    ON i.subject_id = d2.subject_id AND i.hadm_id = d2.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND d1.icd_version = 10 AND d1.icd_code LIKE 'E11%'  -- T2DM
    AND d2.icd_version = 10 AND d2.icd_code LIKE 'I50%'  -- Heart Failure
    AND i.los >= 2  -- ≥48 hours
),

-- Identify GLP-1 medications in pharmacy table that occurred during ICU stay
glp1_medication AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.entertime,
    LOWER(p.medication) AS medication_lower
  FROM physionet-data.mimiciv_3_1_hosp.pharmacy p
  INNER JOIN eligible_patients ep
    ON p.subject_id = ep.subject_id AND p.hadm_id = ep.hadm_id
  WHERE LOWER(p.medication) LIKE '%exenatide%'
     OR LOWER(p.medication) LIKE '%liraglutide%'
     OR LOWER(p.medication) LIKE '%semaglutide%'
     OR LOWER(p.medication) LIKE '%dulaglutide%'
     OR LOWER(p.medication) LIKE '%lixisenatide%'
     OR LOWER(p.medication) LIKE '%albiglutide%'
),

-- Flag if GLP-1 was administered in first 48h or last 12h of ICU stay
flagged_patients AS (
  SELECT
    ep.subject_id,
    ep.stay_id,
    MAX(CASE WHEN gm.entertime BETWEEN ep.intime AND TIMESTAMP_ADD(ep.intime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS glp1_first_48h,
    MAX(CASE WHEN gm.entertime BETWEEN TIMESTAMP_SUB(ep.outtime, INTERVAL 12 HOUR) AND ep.outtime THEN 1 ELSE 0 END) AS glp1_final_12h
  FROM eligible_patients ep
  LEFT JOIN glp1_medication gm
    ON ep.subject_id = gm.subject_id AND ep.hadm_id = gm.hadm_id
  GROUP BY ep.subject_id, ep.stay_id
)

-- Compute prevalence and absolute difference
SELECT
  AVG(glp1_first_48h) AS prevalence_first_48h,
  AVG(glp1_final_12h) AS prevalence_final_12h,
  AVG(glp1_first_48h) - AVG(glp1_final_12h) AS absolute_prevalence_difference
FROM flagged_patients;