WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di1
    ON p.subject_id = di1.subject_id AND a.hadm_id = di1.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d1
    ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di2
    ON p.subject_id = di2.subject_id AND a.hadm_id = di2.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d2
    ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND (
      LOWER(d1.long_title) LIKE '%diabetes%'
      AND LOWER(d2.long_title) LIKE '%heart failure%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

glp1_drugs AS (
  SELECT 'exenatide' AS drug_name UNION ALL
  SELECT 'liraglutide' UNION ALL
  SELECT 'semaglutide' UNION ALL
  SELECT 'dulaglutide' UNION ALL
  SELECT 'lixisenatide' UNION ALL
  SELECT 'tirzepatide' UNION ALL
  SELECT 'albiglutide' UNION ALL
  SELECT 'exenatide extended-release' UNION ALL
  SELECT 'liraglutide injection' UNION ALL
  SELECT 'semaglutide injection' UNION ALL
  SELECT 'dulaglutide injection'
),

prescriptions_in_window AS (
  SELECT 
    ep.subject_id,
    ep.hadm_id,
    ep.admittime,
    ep.dischtime,
    pr.starttime,
    pr.drug
  FROM eligible_patients ep
  INNER JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON ep.subject_id = pr.subject_id AND ep.hadm_id = pr.hadm_id
  INNER JOIN glp1_drugs gd
    ON LOWER(pr.drug) LIKE '%' || LOWER(gd.drug_name) || '%'
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= ep.admittime
    AND pr.starttime <= ep.dischtime
),

first_48h AS (
  SELECT DISTINCT subject_id
  FROM prescriptions_in_window
  WHERE starttime BETWEEN admittime AND admittime + INTERVAL '48' HOUR
),

last_12h AS (
  SELECT DISTINCT subject_id
  FROM prescriptions_in_window
  WHERE starttime BETWEEN dischtime - INTERVAL '12' HOUR AND dischtime
),

prevalence AS (
  SELECT
    COUNT(DISTINCT CASE WHEN f.subject_id IS NOT NULL THEN f.subject_id END) * 100.0 / COUNT(*) AS prevalence_first_48h,
    COUNT(DISTINCT CASE WHEN l.subject_id IS NOT NULL THEN l.subject_id END) * 100.0 / COUNT(*) AS prevalence_last_12h
  FROM eligible_patients ep
  LEFT JOIN first_48h f ON ep.subject_id = f.subject_id
  LEFT JOIN last_12h l ON ep.subject_id = l.subject_id
)

SELECT
  prevalence_first_48h,
  prevalence_last_12h,
  prevalence_last_12h - prevalence_first_48h AS absolute_change,
  CASE 
    WHEN prevalence_first_48h = 0 THEN NULL
    ELSE (prevalence_last_12h - prevalence_first_48h) / prevalence_first_48h * 100
  END AS relative_change_percent
FROM prevalence;