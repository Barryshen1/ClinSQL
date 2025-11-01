WITH t2dm_patients AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE 
    (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
    OR (di.icd_version = 9 AND di.icd_code IN (
      '250.00', '250.02', '250.10', '250.12', '250.20', '250.22', 
      '250.30', '250.32', '250.80', '250.82', '250.90', '250.92'
    ))
),

eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN t2dm_patients t
    ON a.hadm_id = t.hadm_id
  WHERE
    p.gender = 'F'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    AND (
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    ) BETWEEN 59 AND 69
),

glp1_first_48h AS (
  SELECT DISTINCT e.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  INNER JOIN eligible_admissions a
    ON e.hadm_id = a.hadm_id
  WHERE
    e.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND (
      LOWER(e.medication) LIKE '%exenatide%' OR
      LOWER(e.medication) LIKE '%byetta%' OR
      LOWER(e.medication) LIKE '%bydureon%' OR
      LOWER(e.medication) LIKE '%liraglutide%' OR
      LOWER(e.medication) LIKE '%victoza%' OR
      LOWER(e.medication) LIKE '%dulaglutide%' OR
      LOWER(e.medication) LIKE '%trulicity%' OR
      LOWER(e.medication) LIKE '%semaglutide%' OR
      LOWER(e.medication) LIKE '%ozempic%'
    )
    AND LOWER(ed.route) LIKE '%subcut%'
),

glp1_final_12h AS (
  SELECT DISTINCT e.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  INNER JOIN eligible_admissions a
    ON e.hadm_id = a.hadm_id
  WHERE
    e.charttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 12 HOUR) AND a.dischtime
    AND (
      LOWER(e.medication) LIKE '%exenatide%' OR
      LOWER(e.medication) LIKE '%byetta%' OR
      LOWER(e.medication) LIKE '%bydureon%' OR
      LOWER(e.medication) LIKE '%liraglutide%' OR
      LOWER(e.medication) LIKE '%victoza%' OR
      LOWER(e.medication) LIKE '%dulaglutide%' OR
      LOWER(e.medication) LIKE '%trulicity%' OR
      LOWER(e.medication) LIKE '%semaglutide%' OR
      LOWER(e.medication) LIKE '%ozempic%'
    )
    AND LOWER(ed.route) LIKE '%subcut%'
)

SELECT
  (SELECT COUNT(*) FROM glp1_first_48h) * 100.0 / (SELECT COUNT(*) FROM eligible_admissions) AS prevalence_first_48h,
  (SELECT COUNT(*) FROM glp1_final_12h) * 100.0 / (SELECT COUNT(*) FROM eligible_admissions) AS prevalence_final_12h,
  ((SELECT COUNT(*) FROM glp1_first_48h) * 100.0 / (SELECT COUNT(*) FROM eligible_admissions)) -
  ((SELECT COUNT(*) FROM glp1_final_12h) * 100.0 / (SELECT COUNT(*) FROM eligible_admissions)) AS absolute_pp_difference;