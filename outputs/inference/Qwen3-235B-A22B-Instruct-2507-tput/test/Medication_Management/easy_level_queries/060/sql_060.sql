WITH ace_inhibitors AS (
  SELECT 'enalapril' AS drug_name
  UNION ALL SELECT 'lisinopril'
  UNION ALL SELECT 'ramipril'
  UNION ALL SELECT 'captopril'
  UNION ALL SELECT 'benazepril'
  UNION ALL SELECT 'fosinopril'
  UNION ALL SELECT 'moexipril'
  UNION ALL SELECT 'perindopril'
  UNION ALL SELECT 'quinapril'
  UNION ALL SELECT 'trandolapril'
),
patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
),
prescriptions_with_age AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    pa.age_at_admit,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  INNER JOIN
    patient_ages pa
  ON
    pr.subject_id = pa.subject_id
  WHERE
    pa.gender = 'F'
    AND pa.age_at_admit >= 38
    AND pa.age_at_admit <= 48
    AND pr.stoptime IS NOT NULL
),
ace_prescriptions AS (
  SELECT
    pwa.*
  FROM
    prescriptions_with_age pwa
  INNER JOIN
    ace_inhibitors ai
  ON
    LOWER(pwa.drug) LIKE CONCAT('%', ai.drug_name, '%')
)
SELECT
  MAX(duration_days) AS longest_ace_inhibitor_duration_days
FROM
  ace_prescriptions;