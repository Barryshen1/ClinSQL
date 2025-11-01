WITH arb_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.pharmacy_id,
    p.starttime,
    p.stoptime,
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days,
    pat.gender,
    pat.anchor_age,
    adm.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.hadm_id = adm.hadm_id
  WHERE 
    LOWER(p.drug) LIKE ANY(
      '%losartan%', 
      '%valsartan%', 
      '%irbesartan%', 
      '%candesartan%', 
      '%telmisartan%', 
      '%olmesartan%', 
      '%azilsartan%',
      '%cozaar%', 
      '%diovan%', 
      '%avapro%', 
      '%atacand%', 
      '%micardis%', 
      '%benicar%', 
      '%edarbi%'
    )
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 77 AND 87
    AND adm.admission_type != 'OBSERVATION'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) > 0
)

SELECT 
  AVG(duration_days) AS avg_prescription_duration_days
FROM 
  arb_prescriptions;