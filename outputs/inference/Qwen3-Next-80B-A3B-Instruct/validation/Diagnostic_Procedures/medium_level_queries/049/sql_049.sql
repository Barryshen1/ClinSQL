WITH sepsis_no_shock AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
    AND d.icd_code IN ('A41.9', 'R65.20', 'R65.21')  -- sepsis without shock
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = d.hadm_id
        AND d2.icd_version = 10
        AND d2.icd_code = 'R65.22'  -- septic shock
    )
),
admission_duration AS (
  SELECT
    a.hadm_id,
    a.subject_id,  -- Added to enable join with patients
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN sepsis_no_shock s ON a.hadm_id = s.hadm_id
  WHERE a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
patient_filter AS (
  SELECT
    ad.hadm_id,
    ad.los_days,
    p.gender,
    p.anchor_age
  FROM admission_duration ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ad.subject_id = p.subject_id  -- Fixed: join on subject_id, not hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),
procedure_counts AS (
  SELECT
    pf.hadm_id,
    pf.los_days,
    COUNT(pi.icd_code) AS num_procedures
  FROM patient_filter pf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON pf.hadm_id = pi.hadm_id
  GROUP BY pf.hadm_id, pf.los_days
)
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS admission_duration_group,
  AVG(num_procedures) AS mean_diagnostic_procedures
FROM procedure_counts
WHERE los_days BETWEEN 1 AND 7
GROUP BY admission_duration_group
ORDER BY admission_duration_group;