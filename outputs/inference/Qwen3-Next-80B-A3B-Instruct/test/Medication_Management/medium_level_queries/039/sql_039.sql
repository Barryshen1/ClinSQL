WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1 ON p.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddi1 ON d1.icd_code = ddi1.icd_code AND d1.icd_version = ddi1.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2 ON p.subject_id = d2.subject_id AND a.hadm_id = d2.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddi2 ON d2.icd_code = ddi2.icd_code AND d2.icd_version = ddi2.icd_version
  WHERE p.anchor_age BETWEEN 52 AND 62
    AND p.gender = 'M'
    AND LOWER(ddi1.long_title) LIKE LOWER('%diabetes mellitus type 2%')
    AND LOWER(ddi2.long_title) LIKE LOWER('%heart failure%')
),

glp1_prescriptions AS (
  SELECT DISTINCT p.subject_id, p.starttime, p.route
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN eligible_patients e ON p.subject_id = e.subject_id
  WHERE p.starttime >= e.admittime
    AND p.starttime <= e.dischtime
    AND (
      LOWER(p.drug) LIKE LOWER('%exenatide%')
      OR LOWER(p.drug) LIKE LOWER('%liraglutide%')
      OR LOWER(p.drug) LIKE LOWER('%dulaglutide%')
      OR LOWER(p.drug) LIKE LOWER('%semaglutide%')
      OR LOWER(p.drug) LIKE LOWER('%lixisenatide%')
      OR LOWER(p.drug) LIKE LOWER('%albiglutide%')
      OR LOWER(p.drug) LIKE LOWER('%tirzepatide%')
    )
    AND (
      LOWER(p.route) LIKE LOWER('%subcutaneous%')
      OR LOWER(p.route) LIKE LOWER('%injection%')
      OR LOWER(p.route) LIKE LOWER('%sc%')
      OR LOWER(p.route) LIKE LOWER('%subq%')
    )
),

first_24h AS (
  SELECT COUNT(DISTINCT gp.subject_id) AS count_first_24h
  FROM glp1_prescriptions gp
  INNER JOIN eligible_patients e ON gp.subject_id = e.subject_id
  WHERE gp.starttime BETWEEN e.admittime AND e.admittime + INTERVAL '24 hour'
),

last_48h AS (
  SELECT COUNT(DISTINCT gp.subject_id) AS count_last_48h
  FROM glp1_prescriptions gp
  INNER JOIN eligible_patients e ON gp.subject_id = e.subject_id
  WHERE gp.starttime BETWEEN e.dischtime - INTERVAL '48 hour' AND e.dischtime
)

SELECT
  ROUND(100.0 * f.count_first_24h / COUNT(e.subject_id), 2) AS prevalence_first_24h_percent,
  ROUND(100.0 * l.count_last_48h / COUNT(e.subject_id), 2) AS prevalence_last_48h_percent,
  ROUND(100.0 * l.count_last_48h / COUNT(e.subject_id), 2) - ROUND(100.0 * f.count_first_24h / COUNT(e.subject_id), 2) AS absolute_change_percent,
  CASE 
    WHEN f.count_first_24h = 0 THEN NULL
    ELSE ROUND(100.0 * (l.count_last_48h - f.count_first_24h) / f.count_first_24h, 2)
  END AS relative_change_percent
FROM eligible_patients e
CROSS JOIN first_24h f
CROSS JOIN last_48h l;