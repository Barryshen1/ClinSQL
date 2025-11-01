WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 3600 >= 36
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime
  HAVING SUM(CASE WHEN LOWER(d_icd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) >= 1
     AND SUM(CASE WHEN LOWER(d_icd.long_title) LIKE '%acute heart failure%' THEN 1 ELSE 0 END) >= 1
),
glp1_prescriptions AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    pr.starttime
  FROM cohort c
  INNER JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime <= c.dischtime
    AND (
      LOWER(pr.drug) LIKE '%exenatide%'
      OR LOWER(pr.drug) LIKE '%liraglutide%'
      OR LOWER(pr.drug) LIKE '%semaglutide%'
      OR LOWER(pr.drug) LIKE '%dulaglutide%'
      OR LOWER(pr.drug) LIKE '%lixisenatide%'
    )
)
SELECT
  ROUND(
    SUM(CASE WHEN gp.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 24 HOUR THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
  ) AS percent_first_24h,
  ROUND(
    SUM(CASE WHEN gp.starttime BETWEEN c.dischtime - INTERVAL 12 HOUR AND c.dischtime THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
  ) AS percent_final_12h
FROM cohort c
LEFT JOIN glp1_prescriptions gp
  ON c.subject_id = gp.subject_id AND c.hadm_id = gp.hadm_id;