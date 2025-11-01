WITH patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
),
dihydropyridine_drugs AS (
  SELECT 'amlodipine' AS drug_name
  UNION ALL SELECT 'nifedipine'
  UNION ALL SELECT 'felodipine'
  UNION ALL SELECT 'nicardipine'
  UNION ALL SELECT 'nisoldipine'
  UNION ALL SELECT 'isradipine'
  UNION ALL SELECT 'lercanidipine'
  UNION ALL SELECT 'benidipine'
  UNION ALL SELECT 'cilnidipine'
),
prescriptions_with_duration AS (
  SELECT
    pr.subject_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  INNER JOIN
    patient_age pa
  ON
    pr.subject_id = pa.subject_id
  INNER JOIN
    dihydropyridine_drugs d
  ON
    LOWER(pr.drug) LIKE CONCAT('%', d.drug_name, '%')
  WHERE
    pa.gender = 'F'
    AND pa.age_at_admission >= 59
    AND pa.age_at_admission <= 69
    AND pr.drug_type = 'INPATIENT'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
)
SELECT
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(50)] AS median_duration_hours
FROM
  prescriptions_with_duration;