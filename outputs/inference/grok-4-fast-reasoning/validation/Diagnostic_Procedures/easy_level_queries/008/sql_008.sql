WITH cohort AS (
  SELECT DISTINCT subject_id
  FROM (
    SELECT 
      p.subject_id,
      a.admittime,
      p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_adm
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
  )
  WHERE age_at_adm BETWEEN 88 AND 98
),
echo_counts AS (
  SELECT 
    subject_id, 
    COUNT(DISTINCT hcpcs_cd) AS num_distinct
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE hcpcs_cd LIKE '933%'
  GROUP BY subject_id
),
patient_counts AS (
  SELECT COALESCE(ec.num_distinct, 0) AS num_distinct
  FROM cohort c
  LEFT JOIN echo_counts ec 
    ON c.subject_id = ec.subject_id
)
SELECT 
  PERCENTILE_CONT(0.25 ORDER BY num_distinct) AS p25
FROM patient_counts;