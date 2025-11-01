WITH eligible_patients AS (
  -- Get female patients aged 59-69 with hospital stays ≥48h
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),

glp1_medications AS (
  -- List of GLP-1 agonist medications
  SELECT 'exenatide' AS medication UNION ALL
  SELECT 'liraglutide' UNION ALL
  SELECT 'dulaglutide' UNION ALL
  SELECT 'semaglutide' UNION ALL
  SELECT 'lixisenatide' UNION ALL
  SELECT 'albiglutide' UNION ALL
  SELECT 'tirzepatide' -- dual GIP/GLP-1 agonist
),

first_48h_glp1 AS (
  -- Patients with GLP-1 in first 48h
  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id
  FROM
    eligible_patients ep
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ep.hadm_id = pr.hadm_id
  JOIN
    glp1_medications gm
    ON LOWER(pr.drug) LIKE CONCAT('%', LOWER(gm.medication), '%')
  WHERE
    pr.starttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 48 HOUR)

  UNION DISTINCT

  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id
  FROM
    eligible_patients ep
  JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ep.hadm_id = ph.hadm_id
  JOIN
    glp1_medications gm
    ON LOWER(ph.medication) LIKE CONCAT('%', LOWER(gm.medication), '%')
  WHERE
    ph.starttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 48 HOUR)

  UNION DISTINCT

  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id
  FROM
    eligible_patients ep
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
    ON ep.hadm_id = e.hadm_id
  JOIN
    glp1_medications gm
    ON LOWER(e.medication) LIKE CONCAT('%', LOWER(gm.medication), '%')
  WHERE
    e.charttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 48 HOUR)
),

final_12h_glp1 AS (
  -- Patients with GLP-1 in final 12h
  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id
  FROM
    eligible_patients ep
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ep.hadm_id = pr.hadm_id
  JOIN
    glp1_medications gm
    ON LOWER(pr.drug) LIKE CONCAT('%', LOWER(gm.medication), '%')
  WHERE
    pr.starttime BETWEEN TIMESTAMP_SUB(ep.dischtime, INTERVAL 12 HOUR) AND ep.dischtime

  UNION DISTINCT

  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id
  FROM
    eligible_patients ep
  JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ep.hadm_id = ph.hadm_id
  JOIN
    glp1_medications gm
    ON LOWER(ph.medication) LIKE CONCAT('%', LOWER(gm.medication), '%')
  WHERE
    ph.starttime BETWEEN TIMESTAMP_SUB(ep.dischtime, INTERVAL 12 HOUR) AND ep.dischtime

  UNION DISTINCT

  SELECT DISTINCT
    ep.subject_id,
    ep.hadm_id
  FROM
    eligible_patients ep
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
    ON ep.hadm_id = e.hadm_id
  JOIN
    glp1_medications gm
    ON LOWER(e.medication) LIKE CONCAT('%', LOWER(gm.medication), '%')
  WHERE
    e.charttime BETWEEN TIMESTAMP_SUB(ep.dischtime, INTERVAL 12 HOUR) AND ep.dischtime
)

-- Final results
SELECT
  COUNT(DISTINCT ep.subject_id) AS total_eligible_patients,
  COUNT(DISTINCT f48.subject_id) AS first_48h_glp1_patients,
  ROUND(COUNT(DISTINCT f48.subject_id) * 100.0 / COUNT(DISTINCT ep.subject_id), 2) AS first_48h_prevalence,
  COUNT(DISTINCT f12.subject_id) AS final_12h_glp1_patients,
  ROUND(COUNT(DISTINCT f12.subject_id) * 100.0 / COUNT(DISTINCT ep.subject_id), 2) AS final_12h_prevalence,
  ROUND(COUNT(DISTINCT f48.subject_id) * 100.0 / COUNT(DISTINCT ep.subject_id) -
        COUNT(DISTINCT f12.subject_id) * 100.0 / COUNT(DISTINCT ep.subject_id), 2) AS absolute_pp_difference
FROM
  eligible_patients ep
LEFT JOIN
  first_48h_glp1 f48
  ON ep.subject_id = f48.subject_id AND ep.hadm_id = f48.hadm_id
LEFT JOIN
  final_12h_glp1 f12
  ON ep.subject_id = f12.subject_id AND ep.hadm_id = f12.hadm_id;