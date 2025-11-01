WITH qualifying_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),

total_admissions AS (
  SELECT COUNT(*) AS total_count
  FROM qualifying_admissions
),

first_48h_use AS (
  SELECT COUNT(DISTINCT q.hadm_id) AS use_count
  FROM qualifying_admissions q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON q.hadm_id = e.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  WHERE 
    e.charttime >= q.admittime
    AND e.charttime < TIMESTAMP_ADD(q.admittime, INTERVAL 48 HOUR)
    AND (
      LOWER(e.medication) LIKE '%exenatide%'
      OR LOWER(e.medication) LIKE '%liraglutide%'
      OR LOWER(e.medication) LIKE '%dulaglutide%'
      OR LOWER(e.medication) LIKE '%semaglutide%'
      OR LOWER(e.medication) LIKE '%albiglutide%'
      OR LOWER(e.medication) LIKE '%lixisenatide%'
      OR LOWER(e.medication) LIKE '%tirzepatide%'
    )
    AND LOWER(ed.route) IN ('iv', 'subcutaneous', 'intramuscular', 'im', 'sq', 'sub-q')
),

final_12h_use AS (
  SELECT COUNT(DISTINCT q.hadm_id) AS use_count
  FROM qualifying_admissions q
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON q.hadm_id = e.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  WHERE 
    e.charttime >= TIMESTAMP_SUB(q.dischtime, INTERVAL 12 HOUR)
    AND e.charttime <= q.dischtime
    AND (
      LOWER(e.medication) LIKE '%exenatide%'
      OR LOWER(e.medication) LIKE '%liraglutide%'
      OR LOWER(e.medication) LIKE '%dulaglutide%'
      OR LOWER(e.medication) LIKE '%semaglutide%'
      OR LOWER(e.medication) LIKE '%albiglutide%'
      OR LOWER(e.medication) LIKE '%lixisenatide%'
      OR LOWER(e.medication) LIKE '%tirzepatide%'
    )
    AND LOWER(ed.route) IN ('iv', 'subcutaneous', 'intramuscular', 'im', 'sq', 'sub-q')
)

SELECT 
  (f48.use_count * 100.0 / t.total_count) AS prevalence_first_48h_pct,
  (f12.use_count * 100.0 / t.total_count) AS prevalence_final_12h_pct,
  ABS((f48.use_count * 100.0 / t.total_count) - (f12.use_count * 100.0 / t.total_count)) AS absolute_pp_difference
FROM 
  first_48h_use f48,
  final_12h_use f12,
  total_admissions t;